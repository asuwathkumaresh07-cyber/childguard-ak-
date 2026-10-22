enum BlockCategory {
  adult,
  social,
  gambling,
  games,
  streaming,
  violence,
}

extension BlockCategoryX on BlockCategory {
  String get id => name;

  String get label {
    switch (this) {
      case BlockCategory.adult:
        return 'Adult content';
      case BlockCategory.social:
        return 'Social media';
      case BlockCategory.gambling:
        return 'Gambling';
      case BlockCategory.games:
        return 'Games';
      case BlockCategory.streaming:
        return 'Streaming';
      case BlockCategory.violence:
        return 'Violence';
    }
  }

  String get description {
    switch (this) {
      case BlockCategory.adult:
        return 'Pornography and adult sites';
      case BlockCategory.social:
        return 'TikTok, Instagram, Snapchat, X, Reddit';
      case BlockCategory.gambling:
        return 'Betting and casino sites';
      case BlockCategory.games:
        return 'Online gaming platforms';
      case BlockCategory.streaming:
        return 'YouTube, Twitch, Netflix-style sites';
      case BlockCategory.violence:
        return 'Graphic violence content';
    }
  }

  static BlockCategory? fromId(String id) {
    for (final c in BlockCategory.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Curated demo domain lists per category (not exhaustive).
class CategoryDomainLists {
  static const Map<BlockCategory, List<String>> domains = {
    BlockCategory.adult: [
      'pornhub.com',
      'xvideos.com',
      'xnxx.com',
      'xhamster.com',
      'redtube.com',
      'onlyfans.com',
      'chaturbate.com',
    ],
    BlockCategory.social: [
      'tiktok.com',
      'instagram.com',
      'snapchat.com',
      'twitter.com',
      'x.com',
      'reddit.com',
      'facebook.com',
      'discord.com',
      'tumblr.com',
    ],
    BlockCategory.gambling: [
      'bet365.com',
      'draftkings.com',
      'fanduel.com',
      'pokerstars.com',
      'betway.com',
      'casino.com',
    ],
    BlockCategory.games: [
      'roblox.com',
      'minecraft.net',
      'epicgames.com',
      'steampowered.com',
      'twitch.tv',
      'fortnite.com',
    ],
    BlockCategory.streaming: [
      'youtube.com',
      'youtu.be',
      'netflix.com',
      'hulu.com',
      'disneyplus.com',
      'twitch.tv',
      'vimeo.com',
    ],
    BlockCategory.violence: [
      'liveleak.com',
      'bestgore.com',
      'documentingreality.com',
    ],
  };

  static Set<String> domainsFor(Iterable<BlockCategory> categories) {
    final out = <String>{};
    for (final c in categories) {
      out.addAll(domains[c] ?? const []);
    }
    return out;
  }
}

/// Common Android packages parents may want to block.
class CommonBlockedApps {
  static const List<Map<String, String>> presets = [
    {'package': 'com.zhiliaoapp.musically', 'label': 'TikTok'},
    {'package': 'com.ss.android.ugc.trill', 'label': 'TikTok (alt)'},
    {'package': 'com.instagram.android', 'label': 'Instagram'},
    {'package': 'com.snapchat.android', 'label': 'Snapchat'},
    {'package': 'com.twitter.android', 'label': 'X / Twitter'},
    {'package': 'com.reddit.frontpage', 'label': 'Reddit'},
    {'package': 'com.discord', 'label': 'Discord'},
    {'package': 'com.google.android.youtube', 'label': 'YouTube'},
    {'package': 'com.roblox.client', 'label': 'Roblox'},
    {'package': 'com.mojang.minecraftpe', 'label': 'Minecraft'},
    {'package': 'com.netflix.mediaclient', 'label': 'Netflix'},
    {'package': 'com.facebook.katana', 'label': 'Facebook'},
  ];
}
