import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('call ICE configuration keeps STUN and TURN transports available', () {
    final config = CallIceServerConfig.build();
    final servers = config['iceServers'] as List<dynamic>;

    expect(servers, hasLength(2));
    expect(servers.first['urls'], contains('stun:stun.l.google.com:19302'));
    expect(
      servers.last['urls'],
      containsAll([
        'turn:31.129.97.211:3478?transport=udp',
        'turn:31.129.97.211:3478?transport=tcp',
      ]),
    );
    expect(servers.last['username'], isNotEmpty);
    expect(servers.last['credential'], isNotEmpty);
  });

  test('call ICE configuration can be overridden by dart defines', () {
    final config = CallIceServerConfig.build(
      turnUrls: 'turn:example.com:3478?transport=udp, turn:example.com:443?transport=tcp',
      turnUsername: 'demo',
      turnCredential: 'secret',
    );
    final servers = config['iceServers'] as List<dynamic>;

    expect(
      servers.last['urls'],
      ['turn:example.com:3478?transport=udp', 'turn:example.com:443?transport=tcp'],
    );
    expect(servers.last['username'], 'demo');
    expect(servers.last['credential'], 'secret');
  });
}
