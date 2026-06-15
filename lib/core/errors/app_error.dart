enum AppErrorType { network, server, auth, notFound, unknown }

class AppError implements Exception {
  const AppError({required this.type, required this.message, this.statusCode});

  final AppErrorType type;
  final String message;
  final int? statusCode;

  factory AppError.network() => const AppError(
    type: AppErrorType.network,
    message: 'No internet connection.',
  );

  factory AppError.server(int statusCode) => AppError(
    type: AppErrorType.server,
    message: 'Server error ($statusCode).',
    statusCode: statusCode,
  );

  factory AppError.auth() => const AppError(
    type: AppErrorType.auth,
    message: 'Session expired. Please sign in again.',
  );

  factory AppError.notFound() => const AppError(
    type: AppErrorType.notFound,
    message: 'Resource not found.',
  );

  factory AppError.unknown() => const AppError(
    type: AppErrorType.unknown,
    message: 'Something went wrong.',
  );

  @override
  String toString() => 'AppError(${type.name}): $message';
}
