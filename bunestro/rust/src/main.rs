use std::collections::{BTreeSet, VecDeque};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

const DEFAULT_CONCURRENCY: usize = 10;
const MAX_CONCURRENCY: usize = 64;
const STDERR_LIMIT: usize = 64 * 1024;

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(err) => {
            eprintln!("bunestro-rust: {err}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<u8, String> {
    let mut args = env::args_os();
    let _ = args.next();
    match args.next().as_deref().and_then(|arg| arg.to_str()) {
        Some("run") => run_supervised(args.collect()),
        Some("install") => install_manifest(args.collect()),
        Some("cache") => cache_command(args.collect()),
        Some("help") | Some("--help") | Some("-h") | None => {
            print_help();
            Ok(0)
        }
        Some(other) => Err(format!("unknown command '{other}'. Try: bunestro help")),
    }
}

fn print_help() {
    println!(
        "bunestro (Rust)\n\nCommands:\n  run <file.ts|file.js> [args...]   supervise bun run and recover missing packages\n  install [--update] [--package-json path]  install manifest deps into the bunestro cache\n  cache info|dir|list|clean          inspect or clean the cache\n\nEnvironment:\n  BUNESTRO_HOME=/path       cache root (default: ~/.bunestro)\n  BUNESTRO_CONCURRENCY=10   parallel install workers per dependency class"
    );
}

fn bunestro_home() -> PathBuf {
    env::var_os("BUNESTRO_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".bunestro")))
        .unwrap_or_else(|| PathBuf::from(".bunestro"))
}

fn concurrency() -> usize {
    env::var("BUNESTRO_CONCURRENCY")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|value| *value > 0)
        .map(|value| value.min(MAX_CONCURRENCY))
        .unwrap_or(DEFAULT_CONCURRENCY)
}

fn cache_node_modules(home: &Path) -> PathBuf {
    home.join("node_modules")
}

fn run_supervised(args: Vec<OsString>) -> Result<u8, String> {
    if args.is_empty() {
        return Err("missing file for `bunestro run`".into());
    }

    let home = bunestro_home();
    fs::create_dir_all(&home).map_err(|err| format!("create cache: {err}"))?;
    let cache_nm = cache_node_modules(&home);
    let project_nm = env::current_dir()
        .map_err(|err| format!("current dir: {err}"))?
        .join("node_modules");

    let (deps, dev_deps) =
        collect_manifest_dependencies(Path::new("package.json"), &project_nm, &cache_nm, false);
    install_groups_parallel(&home, &deps, &dev_deps, false)?;
    for package in deps.iter().chain(dev_deps.iter()) {
        link_cached_package(&project_nm, &cache_nm, package);
    }

    let node_path = node_path_with_cache(&cache_nm);
    let first = spawn_bun_run(&args, &node_path)?;
    if first.status.success() {
        return Ok(0);
    }

    let Some(package) = extract_missing_package(&first.stderr) else {
        let _ = io::stderr().write_all(&first.stderr);
        return Ok(exit_code(first.status));
    };

    install_packages_parallel(&home, &[package.clone()], false)?;
    link_cached_package(&project_nm, &cache_nm, &package);

    let second = spawn_bun_run(&args, &node_path)?;
    let _ = io::stderr().write_all(&second.stderr);
    Ok(exit_code(second.status))
}

fn install_manifest(args: Vec<OsString>) -> Result<u8, String> {
    let mut update = false;
    let mut package_json = PathBuf::from("package.json");
    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.to_str() {
            Some("--update") => update = true,
            Some("--package-json") => {
                package_json = iter
                    .next()
                    .map(PathBuf::from)
                    .ok_or("--package-json needs a path")?;
            }
            Some(other) => return Err(format!("unknown install option '{other}'")),
            None => return Err("install option is not valid UTF-8".into()),
        }
    }

    let home = bunestro_home();
    let cache_nm = cache_node_modules(&home);
    let (deps, dev_deps) =
        collect_manifest_dependencies(&package_json, Path::new("node_modules"), &cache_nm, update);
    install_groups_parallel(&home, &deps, &dev_deps, update)?;
    Ok(0)
}

fn cache_command(args: Vec<OsString>) -> Result<u8, String> {
    let home = bunestro_home();
    let cache_nm = cache_node_modules(&home);
    let command = args.first().and_then(|arg| arg.to_str()).unwrap_or("info");
    match command {
        "dir" | "path" => println!("{}", home.display()),
        "info" | "stats" => {
            println!("path: {}", home.display());
            println!("packages: {}", count_packages(&cache_nm));
            println!("bytes: {}", dir_size(&home));
            println!("concurrency: {}", concurrency());
        }
        "list" | "ls" => list_packages(&cache_nm),
        "clean" | "prune" => {
            if home.exists() {
                fs::remove_dir_all(&home).map_err(|err| format!("clean cache: {err}"))?;
            }
            println!("removed {}", home.display());
        }
        other => return Err(format!("unknown cache command '{other}'")),
    }
    Ok(0)
}

struct RunOutput {
    status: std::process::ExitStatus,
    stderr: Vec<u8>,
}

fn spawn_bun_run(args: &[OsString], node_path: &OsString) -> Result<RunOutput, String> {
    let mut child = Command::new("bun")
        .arg("run")
        .args(args)
        .env("NODE_PATH", node_path)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| format!("spawn bun run: {err}"))?;

    let mut stderr = Vec::new();
    if let Some(mut pipe) = child.stderr.take() {
        let mut buf = [0u8; 8192];
        loop {
            let read = pipe
                .read(&mut buf)
                .map_err(|err| format!("read stderr: {err}"))?;
            if read == 0 {
                break;
            }
            let remaining = STDERR_LIMIT.saturating_sub(stderr.len());
            if remaining > 0 {
                stderr.extend_from_slice(&buf[..read.min(remaining)]);
            }
        }
    }
    let status = child.wait().map_err(|err| format!("wait bun run: {err}"))?;
    Ok(RunOutput { status, stderr })
}

fn install_groups_parallel(
    home: &Path,
    deps: &[String],
    dev_deps: &[String],
    update: bool,
) -> Result<(), String> {
    let home_deps = home.to_path_buf();
    let deps = deps.to_vec();
    let normal = thread::spawn(move || install_packages_parallel(&home_deps, &deps, update));

    let home_dev = home.to_path_buf();
    let dev_deps = dev_deps.to_vec();
    let dev = thread::spawn(move || install_packages_parallel(&home_dev, &dev_deps, update));

    normal
        .join()
        .map_err(|_| "dependency worker panicked".to_string())??;
    dev.join()
        .map_err(|_| "devDependency worker panicked".to_string())??;
    Ok(())
}

fn install_packages_parallel(home: &Path, packages: &[String], update: bool) -> Result<(), String> {
    if packages.is_empty() {
        return Ok(());
    }
    fs::create_dir_all(home).map_err(|err| format!("create cache: {err}"))?;
    let package_json = home.join("package.json");
    if !package_json.exists() {
        fs::write(&package_json, b"{\"private\":true,\"dependencies\":{}}\n")
            .map_err(|err| format!("write cache package.json: {err}"))?;
    }

    let queue = Arc::new(Mutex::new(VecDeque::from(packages.to_vec())));
    let first_error = Arc::new(Mutex::new(None::<String>));
    let worker_count = packages.len().min(concurrency());
    let mut workers = Vec::with_capacity(worker_count);

    for _ in 0..worker_count {
        let queue = Arc::clone(&queue);
        let first_error = Arc::clone(&first_error);
        let home = home.to_path_buf();
        workers.push(thread::spawn(move || {
            loop {
                if first_error.lock().map_or(true, |error| error.is_some()) {
                    break;
                }
                let Some(package) = queue.lock().ok().and_then(|mut queue| queue.pop_front())
                else {
                    break;
                };
                if let Err(err) = install_package(&home, &package, update) {
                    if let Ok(mut first_error) = first_error.lock() {
                        if first_error.is_none() {
                            *first_error = Some(err);
                        }
                    }
                    break;
                }
            }
        }));
    }

    for worker in workers {
        worker
            .join()
            .map_err(|_| "install worker panicked".to_string())?;
    }
    match Arc::try_unwrap(first_error)
        .ok()
        .and_then(|mutex| mutex.into_inner().ok())
        .flatten()
    {
        Some(err) => Err(err),
        None => Ok(()),
    }
}

fn install_package(home: &Path, package: &str, update: bool) -> Result<(), String> {
    let mut command = Command::new("bun");
    command.arg("add").arg("--no-save");
    if update {
        command.arg("--force").arg("--no-cache");
    }
    let status = command
        .arg(package)
        .current_dir(home)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|err| format!("install {package}: {err}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "install {package} exited with {}",
            exit_code(status)
        ))
    }
}

fn collect_manifest_dependencies(
    path: &Path,
    project_nm: &Path,
    cache_nm: &Path,
    include_cached: bool,
) -> (Vec<String>, Vec<String>) {
    let Ok(source) = fs::read_to_string(path) else {
        return (Vec::new(), Vec::new());
    };
    (
        collect_section(
            &source,
            "dependencies",
            project_nm,
            cache_nm,
            include_cached,
        ),
        collect_section(
            &source,
            "devDependencies",
            project_nm,
            cache_nm,
            include_cached,
        ),
    )
}

fn collect_section(
    source: &str,
    section: &str,
    project_nm: &Path,
    cache_nm: &Path,
    include_cached: bool,
) -> Vec<String> {
    let mut out = Vec::new();
    let Some(section_start) = source.find(&format!("\"{section}\"")) else {
        return out;
    };
    let Some(open_rel) = source[section_start..].find('{') else {
        return out;
    };
    let mut i = section_start + open_rel + 1;
    let bytes = source.as_bytes();
    while i < bytes.len() && bytes[i] != b'}' {
        if bytes[i] == b'"' {
            let start = i + 1;
            if let Some(end_rel) = source[start..].find('"') {
                let end = start + end_rel;
                let name = &source[start..end];
                let after_key = source[end + 1..]
                    .bytes()
                    .position(|byte| !byte.is_ascii_whitespace())
                    .map(|offset| end + 1 + offset);
                if after_key.and_then(|index| bytes.get(index)).copied() == Some(b':')
                    && package_name(name).is_some()
                    && (include_cached || !is_cached(project_nm, cache_nm, name))
                    && !out.iter().any(|item| item == name)
                {
                    out.push(name.to_string());
                }
                i = end + 1;
            }
        }
        i += 1;
    }
    out
}

fn extract_missing_package(stderr: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(stderr);
    for needle in [
        "Cannot find module '",
        "Cannot find package '",
        "Cannot find module \"",
        "Cannot find package \"",
    ] {
        if let Some(start) = text.find(needle) {
            let rest = &text[start + needle.len()..];
            let quote = if needle.ends_with('"') { '"' } else { '\'' };
            if let Some(end) = rest.find(quote) {
                return package_name(&rest[..end]);
            }
        }
    }
    None
}

fn package_name(specifier: &str) -> Option<String> {
    if specifier.is_empty()
        || specifier.starts_with('.')
        || specifier.starts_with('/')
        || specifier.starts_with("node:")
    {
        return None;
    }
    if specifier.starts_with('@') {
        let mut parts = specifier.split('/');
        let scope = parts.next()?;
        let name = parts.next()?;
        Some(format!("{scope}/{name}"))
    } else {
        specifier.split('/').next().map(str::to_string)
    }
}

fn is_cached(project_nm: &Path, cache_nm: &Path, package: &str) -> bool {
    project_nm.join(package).exists() || cache_nm.join(package).exists()
}

fn link_cached_package(project_nm: &Path, cache_nm: &Path, package: &str) {
    let source = cache_nm.join(package);
    if !source.exists() {
        return;
    }
    let dest = project_nm.join(package);
    if dest.exists() {
        return;
    }
    if let Some(parent) = dest.parent() {
        let _ = fs::create_dir_all(parent);
    }
    #[cfg(unix)]
    let _ = std::os::unix::fs::symlink(&source, &dest);
    #[cfg(windows)]
    let _ = std::os::windows::fs::symlink_dir(&source, &dest);
}

fn node_path_with_cache(cache_nm: &Path) -> OsString {
    let mut paths = vec![cache_nm.to_path_buf()];
    if let Some(existing) = env::var_os("NODE_PATH") {
        paths.extend(env::split_paths(&existing));
    }
    env::join_paths(paths).unwrap_or_else(|_| cache_nm.as_os_str().to_owned())
}

fn count_packages(cache_nm: &Path) -> usize {
    let Ok(entries) = fs::read_dir(cache_nm) else {
        return 0;
    };
    let mut names = BTreeSet::new();
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        if name.starts_with('@') {
            if let Ok(scoped) = fs::read_dir(entry.path()) {
                for scoped in scoped.filter_map(Result::ok) {
                    names.insert(format!("{name}/{}", scoped.file_name().to_string_lossy()));
                }
            }
        } else {
            names.insert(name);
        }
    }
    names.len()
}

fn list_packages(cache_nm: &Path) {
    let Ok(entries) = fs::read_dir(cache_nm) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        if name.starts_with('@') {
            if let Ok(scoped) = fs::read_dir(entry.path()) {
                for scoped in scoped.filter_map(Result::ok) {
                    println!("{name}/{}", scoped.file_name().to_string_lossy());
                }
            }
        } else {
            println!("{name}");
        }
    }
}

fn dir_size(path: &Path) -> u64 {
    let Ok(meta) = fs::symlink_metadata(path) else {
        return 0;
    };
    if meta.is_file() {
        return meta.len();
    }
    if !meta.is_dir() {
        return 0;
    }
    fs::read_dir(path)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|entry| dir_size(&entry.path()))
                .sum()
        })
        .unwrap_or(0)
}

fn exit_code(status: std::process::ExitStatus) -> u8 {
    status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1)
}
