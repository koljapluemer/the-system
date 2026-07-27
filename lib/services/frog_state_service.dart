import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Frog flow's cross-session daily-pick cache — the direct
/// analog of the `frog` app's separate `dailySelections`/log tables. This
/// can't live on the picked note itself (see [FrogNotifier] in
/// frog_notifier.dart): a done-and-delete/just-delete action removes that
/// note, but the "already acted today" gate must still hold for the rest of
/// the day.
class FrogStateService {
  const FrogStateService();

  static const _pickedDayKeyKey = 'frogPickedDayKey';
  static const _pickedFilenameKey = 'frogPickedFilename';
  static const _previousDayKeyKey = 'frogPreviousDayKey';
  static const _previousFilenameKey = 'frogPreviousFilename';
  static const _actedDayKeyKey = 'frogActedDayKey';

  Future<String?> getPickedDayKey() async => SharedPreferencesAsync().getString(_pickedDayKeyKey);
  Future<String?> getPickedFilename() async =>
      SharedPreferencesAsync().getString(_pickedFilenameKey);

  Future<void> setPicked({required String dayKey, required String filename}) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_pickedDayKeyKey, dayKey);
    await prefs.setString(_pickedFilenameKey, filename);
  }

  Future<String?> getPreviousDayKey() async =>
      SharedPreferencesAsync().getString(_previousDayKeyKey);
  Future<String?> getPreviousFilename() async =>
      SharedPreferencesAsync().getString(_previousFilenameKey);

  Future<void> setPrevious({required String dayKey, required String filename}) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_previousDayKeyKey, dayKey);
    await prefs.setString(_previousFilenameKey, filename);
  }

  Future<String?> getActedDayKey() async => SharedPreferencesAsync().getString(_actedDayKeyKey);

  Future<void> setActedDayKey(String dayKey) async {
    await SharedPreferencesAsync().setString(_actedDayKeyKey, dayKey);
  }
}
