import '../models/project_file.dart';

/// Message received from the project bridge server.
class BridgeMessage {
  BridgeMessage({
    required this.type,
    this.text = '',
    this.tuiRunning = false,
    this.projectId = '',
    this.sessionId = '',
    this.projects = const [],
    this.messages = const [],
    this.imageBase64 = '',
    this.imageMimeType = '',
    this.imageFilename = '',
    this.files = const [],
    this.filePath = '',
    this.fileSize = 0,
    this.append = false,
    this.isFinal = false,
    this.streamId = '',
    this.runtimeKind = '',
  });

  final String type;
  final String text;
  final bool tuiRunning;
  final String projectId;
  final String sessionId;
  final List<Map<String, dynamic>> projects;
  final List<BridgeMessage> messages;
  final String imageBase64;
  final String imageMimeType;
  final String imageFilename;
  final List<ProjectFileNode> files;
  final String filePath;
  final int fileSize;
  final bool append;
  final bool isFinal;
  final String streamId;
  final String runtimeKind;

  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    return BridgeMessage(
      type: (json['type'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      tuiRunning: json['tui_running'] == true,
      projectId: (json['project_id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      projects: (json['projects'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
      messages: (json['messages'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(BridgeMessage.fromJson)
              .toList() ??
          const [],
      imageBase64: (json['data_base64'] ?? '').toString(),
      imageMimeType: (json['mime_type'] ?? '').toString(),
      imageFilename: (json['filename'] ?? '').toString(),
      files: (json['files'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(ProjectFileNode.fromJson)
              .toList() ??
          const [],
      filePath: (json['path'] ?? '').toString(),
      fileSize: int.tryParse((json['size'] ?? 0).toString()) ?? 0,
      append: json['append'] == true,
      isFinal: json['final'] == true,
      streamId: (json['stream_id'] ?? '').toString(),
      runtimeKind: (json['runtime_kind'] ?? '').toString(),
    );
  }

  BridgeMessage copyWith({
    String? type,
    String? text,
    bool? tuiRunning,
    String? projectId,
    String? sessionId,
    List<Map<String, dynamic>>? projects,
    List<BridgeMessage>? messages,
    String? imageBase64,
    String? imageMimeType,
    String? imageFilename,
    List<ProjectFileNode>? files,
    String? filePath,
    int? fileSize,
    bool? append,
    bool? isFinal,
    String? streamId,
    String? runtimeKind,
  }) {
    return BridgeMessage(
      type: type ?? this.type,
      text: text ?? this.text,
      tuiRunning: tuiRunning ?? this.tuiRunning,
      projectId: projectId ?? this.projectId,
      sessionId: sessionId ?? this.sessionId,
      projects: projects ?? this.projects,
      messages: messages ?? this.messages,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageMimeType: imageMimeType ?? this.imageMimeType,
      imageFilename: imageFilename ?? this.imageFilename,
      files: files ?? this.files,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      append: append ?? this.append,
      isFinal: isFinal ?? this.isFinal,
      streamId: streamId ?? this.streamId,
      runtimeKind: runtimeKind ?? this.runtimeKind,
    );
  }

  bool get isImage => type == 'image' || type == 'sent_image';
  bool get isOutput => type == 'output';
  bool get isStatus => type == 'status';
  bool get isError => type == 'error';
  bool get isSent => type == 'sent' || type == 'sent_image';
  bool get isPong => type == 'pong';
  bool get isProjects => type == 'projects';
  bool get isHistory => type == 'history';
  bool get isSessionInfo => type == 'session_info';
  bool get isFiles => type == 'files';
  bool get isFileContent => type == 'file_content';

  String get fileContentText => text;
  String get fileContentPath =>
      projectId.isNotEmpty ? '$projectId:$text' : text;
  String get fileContentError => text.startsWith('Error:') ? text : '';
}
