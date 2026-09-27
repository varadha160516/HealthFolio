import { NextFunction, Request, Response } from 'express';

type AsyncRouteHandler = (req: Request, res: Response, next: NextFunction) => Promise<unknown>;

/**
 * Express 4 does not await an `async` route handler — if one rejects (including a synchronous
 * throw inside it, e.g. a db.prepare().run() that violates a constraint), the rejection is never
 * caught by Express and becomes an unhandled promise rejection. Node's default
 * (`--unhandled-rejections=throw`) then crashes the entire process, taking the API down for every
 * user over one bad request. This wraps an async handler so any rejection is forwarded to
 * `next(err)` instead, which the global error middleware in app.ts already turns into a clean 500.
 *
 * Every `async (req, res) => {...}` route handler in this codebase must be wrapped in this —
 * see server/src/test/asyncHandler.test.ts for the crash this closes.
 */
export function asyncHandler(fn: AsyncRouteHandler) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
