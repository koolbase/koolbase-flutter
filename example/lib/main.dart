import 'package:flutter/material.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'offline_probe.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Koolbase.initialize(
    const KoolbaseConfig(
      publicKey: 'pk_test_76a8e292268c362133314b1f',
      baseUrl: 'https://api.koolbase.com',
      refreshInterval: Duration(seconds: 30),
    ),
  );

  final versionCheck = Koolbase.checkVersion();
  if (versionCheck.status == VersionStatus.forceUpdate) {
    runApp(ForceUpdateApp(message: versionCheck.message));
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Koolbase Example', home: HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final showNewAuthFlow = Koolbase.isEnabled('new_auth_flow');
    final swapTimeout = Koolbase.configInt('swap_timeout_config', fallback: 30);
    final versionCheck = Koolbase.checkVersion();

    return Scaffold(
      appBar: AppBar(title: const Text('Koolbase Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID: ${Koolbase.deviceId}'),
            Text('Payload Version: ${Koolbase.payloadVersion}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OfflineProbe())),
              child: const Text('Offline probe'),
            ),
            const SizedBox(height: 16),
            Text('new_auth_flow enabled: $showNewAuthFlow'),
            Text('swap_timeout_config: ${swapTimeout}s'),
            const SizedBox(height: 16),
            if (showNewAuthFlow)
              ElevatedButton(
                onPressed: () {},
                child: const Text('New Auth Flow'),
              )
            else
              ElevatedButton(
                onPressed: () {},
                child: const Text('Legacy Auth Flow'),
              ),
            if (versionCheck.status == VersionStatus.softUpdate)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                color: Colors.amber[100],
                child: Text(
                  versionCheck.message.isNotEmpty
                      ? versionCheck.message
                      : 'A new version is available!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ForceUpdateApp extends StatelessWidget {
  final String message;
  const ForceUpdateApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Update Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message.isNotEmpty
                      ? message
                      : 'Please update the app to continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Update Now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
