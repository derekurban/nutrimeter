// Credentials never live in the repo. Each Supabase environment has a file in ~/.keys/nutrimeter/, as written by
// `supabase branches get <name> -o json`: supabase-dev.env (the `dev` branch), supabase-staging.env (the
// `staging` branch) and supabase-prod.env (the main project). The site offers whichever files exist and switches
// between them per request; NUTRIMETER_ENV picks the one it opens on (and the one the database tests use).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const ENVIRONMENTS = [
  { name: 'dev', label: 'Dev', branch: 'dev' },
  { name: 'staging', label: 'Staging', branch: 'staging' },
  { name: 'prod', label: 'Prod', branch: 'main' },
];

export function keysDir(env = process.env) {
  return env.NUTRIMETER_KEYS_DIR || path.join(os.homedir(), '.keys', 'nutrimeter');
}

export function envName(env = process.env) {
  return env.NUTRIMETER_ENV || 'dev';
}

export function envFile(name, env = process.env) {
  return path.join(keysDir(env), `supabase-${name}.env`);
}

export function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
  }
  return out;
}

/** The environments whose credentials file exists, in dev → staging → prod order. */
export function availableEnvironments(env = process.env) {
  return ENVIRONMENTS.filter((e) => fs.existsSync(envFile(e.name, env)));
}

/** Settings that don't depend on the environment. */
export function siteConfig(env = process.env) {
  return {
    defaultEnv: envName(env),
    reviewer: env.NUTRIMETER_REVIEWER || os.userInfo().username,
    codexModel: env.NUTRIMETER_CODEX_MODEL || null,
    codexEffort: env.NUTRIMETER_CODEX_EFFORT || null,
    artModel: env.NUTRIMETER_ART_MODEL || env.NUTRIMETER_CODEX_MODEL || null,
    artEffort: env.NUTRIMETER_ART_EFFORT || 'medium',
    port: Number(env.NUTRIMETER_ADMIN_PORT || 4317),
  };
}

/** One environment's connection settings. */
export function loadConfig(name = envName(), env = process.env) {
  const known = ENVIRONMENTS.find((e) => e.name === name);
  if (!known) throw new Error(`Unknown environment "${name}": ${ENVIRONMENTS.map((e) => e.name).join(', ')}.`);
  const file = envFile(name, env);
  if (!fs.existsSync(file)) throw new Error(`No credentials at ${file}. See admin/README.md.`);
  const values = parseEnv(fs.readFileSync(file, 'utf8'));
  for (const k of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) if (!values[k]) throw new Error(`${file} is missing ${k}.`);
  return {
    ...siteConfig(env),
    name,
    label: known.label,
    branch: known.branch,
    file,
    supabaseUrl: values.SUPABASE_URL,
    serviceKey: values.SUPABASE_SERVICE_ROLE_KEY,
    publishableKey: values.SUPABASE_PUBLISHABLE_KEY || values.SUPABASE_ANON_KEY || null,
    databaseUrl: values.POSTGRES_URL_NON_POOLING || values.POSTGRES_URL || null,
  };
}
