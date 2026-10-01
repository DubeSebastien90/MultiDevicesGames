import 'dart:math';

class PlayerNames {
  const PlayerNames._();

  static const adjectives = <String>[
    'Angry',
    'Bouncy',
    'Brave',
    'Cheeky',
    'Clumsy',
    'Cosmic',
    'Curious',
    'Dizzy',
    'Explosive',
    'Fearless',
    'Fluffy',
    'Funny',
    'Greedy',
    'Grumpy',
    'Jolly',
    'Lucky',
    'Mighty',
    'Nervous',
    'Rowdy',
    'Salty',
    'Shy',
    'Sleepy',
    'Sneaky',
    'Speedy',
    'Spicy',
    'Stubborn',
    'Thirsty',
    'Wild',
    'Wobbly',
    'Zesty',
  ];

  static const animals = <String>[
    'Badger',
    'Beaver',
    'Cobra',
    'Dingo',
    'Emu',
    'Falcon',
    'Ferret',
    'Gecko',
    'Hamster',
    'Hippo',
    'Iguana',
    'Jackal',
    'Koala',
    'Llama',
    'Lobster',
    'Moose',
    'Narwhal',
    'Ocelot',
    'Otter',
    'Panda',
    'Penguin',
    'Quokka',
    'Raccoon',
    'Salmon',
    'Tapir',
    'Urchin',
    'Viper',
    'Walrus',
    'Yak',
    'Zebra',
  ];

  static String random([Random? random]) {
    final rng = random ?? Random.secure();
    return '${adjectives[rng.nextInt(adjectives.length)]}'
        '${animals[rng.nextInt(animals.length)]}';
  }

  static bool isGenerated(String name) {
    for (final adjective in adjectives) {
      if (!name.startsWith(adjective)) continue;
      if (animals.contains(name.substring(adjective.length))) return true;
    }
    return false;
  }
}
