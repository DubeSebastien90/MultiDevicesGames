import 'dart:math';

/// A name to be going on with: **AngryHippo**, **SleepyOtter**, **SpicyYak**.
///
/// Somebody has to be called something. The standings are read by name, and a
/// table of phones all called "phone" tells nobody anything — but a text field
/// waiting to be filled in is a small wall between opening the app and playing.
/// So a name is picked the first time and kept, and anyone who dislikes theirs
/// types over it.
///
/// Thirty of each makes nine hundred names, which is plenty for a table of six
/// and short of the effort of guaranteeing no repeats — two SpicyYaks is a good
/// evening, not a bug.
class PlayerNames {
  const PlayerNames._();

  /// Chosen to read as a *character*: how somebody plays, or how they are
  /// taking it. Nothing insulting — this lands on a stranger's phone.
  static const adjectives = <String>[
    'Angry', 'Bouncy', 'Brave', 'Cheeky', 'Clumsy',
    'Cosmic', 'Curious', 'Dizzy', 'Explosive', 'Fearless',
    'Fluffy', 'Funny', 'Greedy', 'Grumpy', 'Jolly',
    'Lucky', 'Mighty', 'Nervous', 'Rowdy', 'Salty',
    'Shy', 'Sleepy', 'Sneaky', 'Speedy', 'Spicy',
    'Stubborn', 'Thirsty', 'Wild', 'Wobbly', 'Zesty',
  ];

  /// Short and recognisable, because this is read across a table at a glance.
  static const animals = <String>[
    'Badger', 'Beaver', 'Cobra', 'Dingo', 'Emu',
    'Falcon', 'Ferret', 'Gecko', 'Hamster', 'Hippo',
    'Iguana', 'Jackal', 'Koala', 'Llama', 'Lobster',
    'Moose', 'Narwhal', 'Ocelot', 'Otter', 'Panda',
    'Penguin', 'Quokka', 'Raccoon', 'Salmon', 'Tapir',
    'Urchin', 'Viper', 'Walrus', 'Yak', 'Zebra',
  ];

  /// One of each, stuck together.
  ///
  /// [Random.secure] by default rather than the ordinary one: several phones
  /// opening the app at the same moment would otherwise seed from the same
  /// clock and all arrive at the table with the same name. Pass a seeded
  /// [random] to get the same name every time.
  static String random([Random? random]) {
    final rng = random ?? Random.secure();
    return '${adjectives[rng.nextInt(adjectives.length)]}'
        '${animals[rng.nextInt(animals.length)]}';
  }

  /// Whether [name] is one this class could have produced.
  ///
  /// The child guard needs to answer "is the name on this phone a made-up one,
  /// or did somebody type it?", and it has to answer that on **every** load,
  /// not once. A phone can arrive at the child state carrying a name from
  /// before it got there — an install that predates the age question, or a
  /// household where the adult set the phone up and the child then answered for
  /// themselves. Checking the shape of the stored string catches all of those
  /// without needing to have witnessed how it got written.
  ///
  /// Exact, case-sensitive matching against the two lists. Anything looser —
  /// "starts with a known adjective", say — would pass `SpicyYak Smith`, and
  /// the surname is the entire thing being kept off the network.
  static bool isGenerated(String name) {
    for (final adjective in adjectives) {
      if (!name.startsWith(adjective)) continue;
      if (animals.contains(name.substring(adjective.length))) return true;
    }
    return false;
  }
}
