import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runMigrations } from './migrate.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Tests set CARELOOP_DB_PATH=:memory: for a fresh, isolated database per run.
let dbPath = process.env.CARELOOP_DB_PATH;
if (!dbPath) {
  const dataDir = path.resolve(__dirname, '../../data');
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
  dbPath = path.join(dataDir, 'careloop.sqlite');
}

/**
 * Uses Node's built-in `node:sqlite` (stable from Node 22.5+) rather than better-sqlite3 — this
 * environment has no Python/C++ build toolchain available for better-sqlite3's native addon, and
 * the built-in module needs no compilation at all. API is intentionally kept close to
 * better-sqlite3's (prepare/run/get/all, named @params) so the rest of the codebase reads the same.
 */
export class Db {
  private raw: DatabaseSync;
  constructor(file: string) {
    this.raw = new DatabaseSync(file);
    this.raw.exec('PRAGMA journal_mode = WAL');
    this.raw.exec('PRAGMA foreign_keys = ON');
  }
  exec(sql: string) {
    this.raw.exec(sql);
  }
  prepare(sql: string) {
    return this.raw.prepare(sql);
  }
  /** Mimics better-sqlite3's db.transaction(fn) — returns a callable that wraps fn in BEGIN/COMMIT. */
  transaction<T extends (...args: any[]) => any>(fn: T): (...args: Parameters<T>) => ReturnType<T> {
    return (...args: Parameters<T>): ReturnType<T> => {
      this.raw.exec('BEGIN');
      try {
        const result = fn(...args);
        this.raw.exec('COMMIT');
        return result;
      } catch (err) {
        this.raw.exec('ROLLBACK');
        throw err;
      }
    };
  }
}

export const db = new Db(dbPath);

const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf-8');
db.exec(schema);
runMigrations(db);

export function now(): string {
  return new Date().toISOString();
}
