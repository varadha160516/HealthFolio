// Sets test-only env before anything else loads, cross-platform (avoids `KEY=value cmd` shell
// syntax that cmd.exe doesn't support). Loaded via `node --import` ahead of the tsx loader.
process.env.CARELOOP_DB_PATH = ':memory:';
