import cors from "@fastify/cors";
import fastifyStatic from "@fastify/static";
import { serve } from "@hono/node-server";
import { Type } from "@sinclair/typebox";
import { QueryClient } from "@tanstack/query-core";
import axios from "axios";
import chalk from "chalk";
import { Command } from "commander";
import { formatISO } from "date-fns";
import dotenv from "dotenv";
import { sql } from "drizzle-orm";
import Fastify from "fastify";
import { Hono } from "hono";
import Redis from "ioredis";
import { SignJWT } from "jose";
import { chunk } from "lodash-es";
import { minimatch } from "minimatch";
import { nanoid } from "nanoid";
import pino from "pino";
import postgres from "postgres";
import React from "react";
import { renderToString } from "react-dom/server";
import { of } from "rxjs";
import sharp from "sharp";
import { Server } from "socket.io";
import { fetch } from "undici";
import * as v from "valibot";
import WebSocket from "ws";
import YAML from "yaml";
import { z } from "zod";

import { ESLint } from "eslint";
import prettier from "prettier";
import "tsx";
import ts from "typescript";
import { defineConfig } from "vite";
import { expect, test } from "vitest";

const checks = {
  cors: typeof cors,
  fastifyStatic: typeof fastifyStatic,
  serve: typeof serve,
  typebox: Type.String().type,
  queryClient: typeof QueryClient,
  axios: typeof axios.get,
  chalk: chalk.green("ok"),
  commander: new Command().name("bunx-cache-example").name(),
  dateFns: formatISO(new Date(0)),
  dotenv: typeof dotenv.config,
  drizzle: typeof sql,
  fastify: typeof Fastify,
  hono: new Hono().routes.length,
  ioredis: typeof Redis,
  jose: typeof SignJWT,
  lodash: chunk([1, 2, 3, 4], 2).length,
  minimatch: minimatch("src/index.ts", "src/**/*.ts"),
  nanoid: typeof nanoid(),
  pino: typeof pino,
  postgres: typeof postgres,
  react: React.createElement("span", null, "ok").type,
  reactDom: renderToString(React.createElement("span", null, "ok")),
  rxjs: typeof of,
  sharp: typeof sharp,
  socketIo: typeof Server,
  undici: typeof fetch,
  valibot: v.string().type,
  ws: typeof WebSocket,
  yaml: YAML.stringify({ ok: true }).trim(),
  zod: z.string().parse("ok"),
  eslint: typeof ESLint,
  prettier: typeof prettier.format,
  typescript: ts.versionMajorMinor,
  vite: typeof defineConfig,
  vitest: typeof test + ":" + typeof expect,
};

console.log(JSON.stringify(checks, null, 2));
