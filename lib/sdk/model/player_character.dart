library;

import 'player_color.dart';

class PlayerCharacter {
  const PlayerCharacter({
    required this.colorId,
    required this.name,
    this.topdownAsset,
    this.faceAsset,
    this.happyAsset,
    this.sadAsset,
  });

  final String colorId;

  final String name;

  final String? topdownAsset;

  final String? faceAsset;

  final String? happyAsset;
  final String? sadAsset;

  @override
  String toString() => 'PlayerCharacter($colorId/$name)';
}

class Cast {
  const Cast._();

  static const green = PlayerCharacter(
    colorId: 'green',
    name: 'Frog',
    topdownAsset: 'assets/sdk/players/green-topdown.png',
    faceAsset: 'assets/sdk/players/green-face.png',
    happyAsset: 'assets/sdk/players/green-happy.wav',
    sadAsset: 'assets/sdk/players/green-sad.wav',
  );

  static const orange = PlayerCharacter(
    colorId: 'orange',
    name: 'Fox',
    topdownAsset: 'assets/sdk/players/orange-topdown.png',
    faceAsset: 'assets/sdk/players/orange-face.png',
    happyAsset: 'assets/sdk/players/orange-happy.wav',
    sadAsset: 'assets/sdk/players/orange-sad.wav',
  );

  static const blue = PlayerCharacter(
    colorId: 'blue',
    name: 'Whale',
    topdownAsset: 'assets/sdk/players/blue-topdown.png',
    faceAsset: 'assets/sdk/players/blue-face.png',
    happyAsset: 'assets/sdk/players/blue-happy.wav',
    sadAsset: 'assets/sdk/players/blue-sad.wav',
  );

  static const pink = PlayerCharacter(
    colorId: 'pink',
    name: 'Flamingo',
    topdownAsset: 'assets/sdk/players/pink-topdown.png',
    faceAsset: 'assets/sdk/players/pink-face.png',
    happyAsset: 'assets/sdk/players/pink-happy.wav',
    sadAsset: 'assets/sdk/players/pink-sad.wav',
  );

  static const yellow = PlayerCharacter(
    colorId: 'yellow',
    name: 'Bee',
    topdownAsset: 'assets/sdk/players/yellow-topdown.png',
    faceAsset: 'assets/sdk/players/yellow-face.png',
    happyAsset: 'assets/sdk/players/yellow-happy.wav',
    sadAsset: 'assets/sdk/players/yellow-sad.wav',
  );

  static const purple = PlayerCharacter(
    colorId: 'purple',
    name: 'Octopus',
    topdownAsset: 'assets/sdk/players/purple-topdown.png',
    faceAsset: 'assets/sdk/players/purple-face.png',
    happyAsset: 'assets/sdk/players/purple-happy.wav',
    sadAsset: 'assets/sdk/players/purple-sad.wav',
  );

  static const brown = PlayerCharacter(
    colorId: 'brown',
    name: 'Bear',
    topdownAsset: 'assets/sdk/players/brown-topdown.png',
    faceAsset: 'assets/sdk/players/brown-face.png',
    happyAsset: 'assets/sdk/players/brown-happy.wav',
    sadAsset: 'assets/sdk/players/brown-sad.wav',
  );

  static const red = PlayerCharacter(
    colorId: 'red',
    name: 'Crab',
    topdownAsset: 'assets/sdk/players/red-topdown.png',
    faceAsset: 'assets/sdk/players/red-face.png',
    happyAsset: 'assets/sdk/players/red-happy.wav',
    sadAsset: 'assets/sdk/players/red-sad.wav',
  );

  static const all = <PlayerCharacter>[
    green,
    orange,
    blue,
    pink,
    yellow,
    purple,
    brown,
    red,
  ];

  static PlayerCharacter of(PlayerColor color) => byColorId(color.id) ?? green;

  static PlayerCharacter? byColorId(String colorId) {
    for (final c in all) {
      if (c.colorId == colorId) return c;
    }
    return null;
  }
}
