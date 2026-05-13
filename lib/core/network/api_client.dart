// Add `dio: ^5.x.x` to pubspec.yaml before using this file.
// import 'package:dio/dio.dart';


class ApiClient {
  static const String railwayBaseUrl = 'syncraflutter-production.up.railway.app';
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  String? token;

  // Replace with real Dio instance once dio is added to pubspec.
  // final Dio _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Future<Map<String, dynamic>> get(String path) async {
    throw UnimplementedError('Wire up Dio: GET $baseUrl$path');
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    throw UnimplementedError('Wire up Dio: POST $baseUrl$path');
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    throw UnimplementedError('Wire up Dio: PUT $baseUrl$path');
  }

  Future<void> delete(String path) async {
    throw UnimplementedError('Wire up Dio: DELETE $baseUrl$path');
  }
}
