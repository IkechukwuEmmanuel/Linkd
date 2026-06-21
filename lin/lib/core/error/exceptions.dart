abstract class AppException implements Exception {
  final String message;

  AppException(this.message);

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException([super.message = 'Network error occurred']);
}

class ServerException extends AppException {
  final int? statusCode;

  ServerException(
    super.message, {
    this.statusCode,
  });
}

class CacheException extends AppException {
  CacheException([super.message = 'Cache error occurred']);
}

class ValidationException extends AppException {
  ValidationException([super.message = 'Validation error occurred']);
}

class UnauthorizedException extends AppException {
  UnauthorizedException([super.message = 'Unauthorized access']);
}

class TimeoutException extends AppException {
  TimeoutException([super.message = 'Request timeout']);
}

class NotFoundException extends AppException {
  NotFoundException([super.message = 'Resource not found']);
}
