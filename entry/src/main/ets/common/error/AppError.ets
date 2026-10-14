/**
 * 应用统一错误类型：所有跨层上抛的错误一律包装为 AppError，携带 ErrorCode 码值。
 */

export class AppError extends Error {
  readonly code: number;
  readonly cause?: Error;

  constructor(code: number, message: string, cause?: Error) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.cause = cause;
  }

  /** 将原生 Error 包装为 AppError，保留原始错误为 cause */
  static fromError(code: number, error: Error): AppError {
    return new AppError(code, error.message, error);
  }
}
