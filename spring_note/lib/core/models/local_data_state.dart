import 'app_config.dart';
import 'note_file.dart';
import 'package:path/path.dart' as p;

class LocalDataState {
  const LocalDataState({
    required this.dataDirectory,
    required this.configPath,
    required this.dailyNotesDirectory,
    required this.weeklyNotesDirectory,
    required this.monthlyNotesDirectory,
    required this.config,
  });

  final String dataDirectory;
  final String configPath;
  final String dailyNotesDirectory;
  final String weeklyNotesDirectory;
  final String monthlyNotesDirectory;
  final AppConfig config;

  String directoryFor(NoteKind kind) => switch (kind) {
    NoteKind.daily => dailyNotesDirectory,
    NoteKind.weekly => weeklyNotesDirectory,
    NoteKind.monthly => monthlyNotesDirectory,
    _ => p.join(dataDirectory, 'notes', kind.directoryName),
  };

  LocalDataState copyWith({
    String? dataDirectory,
    String? configPath,
    String? dailyNotesDirectory,
    String? weeklyNotesDirectory,
    String? monthlyNotesDirectory,
    AppConfig? config,
  }) {
    return LocalDataState(
      dataDirectory: dataDirectory ?? this.dataDirectory,
      configPath: configPath ?? this.configPath,
      dailyNotesDirectory: dailyNotesDirectory ?? this.dailyNotesDirectory,
      weeklyNotesDirectory: weeklyNotesDirectory ?? this.weeklyNotesDirectory,
      monthlyNotesDirectory:
          monthlyNotesDirectory ?? this.monthlyNotesDirectory,
      config: config ?? this.config,
    );
  }
}
