/// Un servidor Komga configurado en la app.
///
/// El secreto (contraseña o API key) no se guarda aquí: vive en el
/// almacenamiento seguro del dispositivo (ver [SourceStore]).
enum AuthType { apiKey, basic }

class Source {
  final String id;
  final String name;
  final String baseUrl;
  final AuthType authType;
  final String username;

  const Source({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.authType,
    this.username = '',
  });

  Source copyWith({String? name, String? baseUrl, AuthType? authType, String? username}) => Source(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    authType: authType ?? this.authType,
    username: username ?? this.username,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'authType': authType.name,
    'username': username,
  };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
    id: j['id'] as String,
    name: j['name'] as String,
    baseUrl: j['baseUrl'] as String,
    authType: AuthType.values.byName(j['authType'] as String),
    username: j['username'] as String? ?? '',
  );

  /// Normaliza lo que pega el usuario: quita "/dashboard", barras finales, etc.
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.parse(url);
    var path = uri.path;
    for (final suffix in ['/dashboard', '/libraries']) {
      final i = path.indexOf(suffix);
      if (i >= 0) path = path.substring(0, i);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path).toString();
  }
}
