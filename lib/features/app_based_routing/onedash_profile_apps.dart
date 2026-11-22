import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/app_based_routing/data/selected_data_provider.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_backup.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// OneDash: the `per-app-proxy` value last applied, so a profile update applies a list only once.
final _appliedPerAppProxy = PreferencesNotifier.create<String, String>("onedash_per_app_proxy_applied", "");

/// OneDash: the active profile's `per-app-proxy` header, base64 of a JSON list of package names, is
/// added to App-based routing in Exclude mode and turns it on: those apps bypass the tunnel and don't
/// see the VPN. The user's own choices stay, an app the user unticked stays unticked. Android only;
/// watched in App like appBasedRoutingProvider, which turns the list into the excluded packages.
final oneDashProfileAppsProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<ProfileEntity?>>(activeProfileProvider, (_, next) {
    final value = next.valueOrNull?.populatedHeaders?['per-app-proxy']?.toString().trim();
    if (value == null || value.isEmpty || value == ref.read(_appliedPerAppProxy)) return;
    unawaited(_apply(ref, value));
  }, fireImmediately: true);
});

Future<void> _apply(Ref ref, String value) async {
  final List<String> packages;
  try {
    packages = (jsonDecode(utf8.decode(base64.decode(base64.normalize(value)))) as List).cast<String>();
  } catch (_) {
    return;
  }
  final ds = ref.read(appProxyDataSourceProvider);
  const exclude = AppProxyMode.exclude;
  const include = AppProxyMode.include;
  final unticked = (await ds.getPkgsByFlag(mode: exclude, flag: PkgFlag.forceDeselection)).toSet();
  final ticked = (await ds.getPkgsByFlag(mode: exclude, flag: PkgFlag.userSelection)).toSet();
  await ds.importPkgs(
    backup: PerAppProxyBackup(
      include: PerAppProxyBackupMode(
        selected: await ds.getPkgsByFlag(mode: include, flag: PkgFlag.userSelection),
        deselected: await ds.getPkgsByFlag(mode: include, flag: PkgFlag.forceDeselection),
      ),
      exclude: PerAppProxyBackupMode(
        selected: {...ticked, ...packages.where((pkg) => !unticked.contains(pkg))}.toList(),
        deselected: unticked.toList(),
      ),
    ),
  );
  await ref.read(Preferences.perAppProxyMode.notifier).update(exclude);
  await ref.read(Preferences.perAppProxyEnabled.notifier).update(true);
  await ref.read(_appliedPerAppProxy.notifier).update(value);
}
