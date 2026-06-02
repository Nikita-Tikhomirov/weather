from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
STICKER_ROOT = PROJECT_ROOT / "assets" / "stickers"
CATALOG_DIR = STICKER_ROOT / "catalog"
SOURCE_DIR = STICKER_ROOT / "source_grids_v2"
LIBRARY_DIR = STICKER_ROOT / "library_v2"
GRID_SIZE = 25
PROMPT_VERSION = 2


CELL_DIRECTIONS = [
    "front-facing standing pose, red heart pillow, round silhouette",
    "side-facing sitting pose, blue ceramic mug, low wide silhouette",
    "tiny jump pose, yellow star badge, paws lifted",
    "curled pose, purple blanket roll, compact silhouette",
    "leaning pose, orange keyring, one paw forward",
    "dramatic arms-wide pose, pink toy megaphone with no text, tall silhouette",
    "sleepy slouch pose, cream moon cushion, heavy eyelids",
    "sneaky tiptoe pose, black-and-white checker scarf, narrow silhouette",
    "proud chest-out pose, gold paper crown with no text, chin raised",
    "tiny panic run pose, red-and-blue ribbon trail, motion lines",
    "calm seated pose, lavender teacup, soft smile",
    "confused head-tilt pose, tan paper map with no writing, asymmetrical silhouette",
    "victory hop pose, white tiny flag with no symbol, one foot up",
    "bashful tucked-paws pose, rose gift box, small blush",
    "skeptical side-eye pose, gray magnifying glass, angled eyebrows",
    "overthinking crouch pose, navy puzzle piece, paws on cheeks",
    "surprised backward-lean pose, peach balloon, open mouth",
    "focused tiny-work pose, brown clipboard with no writing, narrowed eyes",
    "relaxed blanket pose, ivory pillow stack, soft rounded outline",
    "idea pose, amber lightbulb prop, bright eyes",
    "tiny dance pose, magenta party streamer, one paw overhead",
    "protective hug pose, sky-blue plush cloud, closed-eye smile",
    "determined march pose, copper tiny shield with no emblem, forward lean",
    "awkward freeze pose, lilac soap bubble, stiff little paws",
    "celebration spin pose, silver confetti swirl, wide happy face",
]


ACCENT_COLORS = [
    "coral",
    "crimson",
    "ruby",
    "scarlet",
    "rose",
    "blush-pink",
    "fuchsia",
    "magenta",
    "lilac",
    "lavender",
    "violet",
    "plum",
    "indigo",
    "navy",
    "cobalt",
    "sapphire",
    "sky-blue",
    "periwinkle",
    "amber",
    "gold",
    "lemon-yellow",
    "butter-yellow",
    "peach",
    "apricot",
    "tangerine",
    "orange",
    "copper",
    "bronze",
    "caramel",
    "chocolate",
    "mocha",
    "ivory",
    "cream",
    "pearl-white",
    "silver",
    "graphite",
    "charcoal",
    "black",
    "white",
    "slate",
    "mauve",
    "burgundy",
    "raspberry",
    "salmon",
    "terracotta",
    "sand",
    "clay",
    "orchid",
    "midnight-blue",
    "warm-gray",
]


ACCENT_DETAILS = [
    "tiny star patch",
    "round button pin",
    "striped scarf knot",
    "paperclip charm",
    "heart-shaped patch",
    "crescent moon charm",
    "dotted bow tie",
    "checker wristband",
    "small ribbon loop",
    "tiny lightning charm",
    "mini cloud puff",
    "single confetti burst",
    "toy camera strap",
    "little badge shape",
    "tiny folded napkin",
    "soft pom-pom",
    "small blanket tassel",
    "toy compass charm",
    "tiny paper crown trim",
    "small scarf fringe",
    "mini flower-shaped pin",
    "single sparkle cluster",
    "little stitched pocket",
    "tiny pillow corner",
    "small teacup charm",
    "mini bookmark ribbon",
    "tiny donut-shaped patch",
    "little envelope charm",
    "small sock cuff",
    "mini umbrella handle",
    "single bubble accent",
    "tiny medal ribbon",
    "small toy shield edge",
    "mini star wand tip",
    "little bow on tail",
    "tiny leaf-shaped patch",
    "small quilt square",
    "mini keychain ring",
    "tiny candle flame shape",
    "little sleepy cap trim",
    "small notebook corner",
    "mini spoon charm",
    "tiny music-note charm without text",
    "single snowflake charm",
    "little cupcake wrapper",
    "small map corner without writing",
    "mini rocket patch",
    "tiny suitcase tag without text",
    "single spiral accent",
    "little toy wheel",
]


STYLE_DESCRIPTIONS = {
    "plush_3d": (
        "polished 3D toy/plush sticker, soft rounded forms, tactile felt and "
        "vinyl details, cute expressive face, premium mobile sticker look"
    ),
    "meme_wobbly": (
        "funny meme sticker, deliberately wobbly awkward drawing, expressive "
        "pose, chaotic but charming, clean enough for a mobile app"
    ),
}


CHARACTER_DESCRIPTIONS = {
    "rats": "small clever rats with long tails, rounded ears, bright eyes",
    "hedgehogs": "small hedgehogs with soft rounded spines, tiny paws, expressive eyes",
    "duos": "one rat and one hedgehog interacting as a duo",
    "mixed": "rats and hedgehogs, sometimes solo and sometimes together",
}


CONCEPT_POOLS = {
    "emotions": [
        "happy nod", "sleepy blink", "shocked stare", "proud pose",
        "tiny panic", "guilty smile", "soft sadness", "angry pout",
        "curious sniff", "dramatic gasp", "relieved sigh", "confused tilt",
        "victory cheer", "bashful blush", "skeptical look", "silent judging",
        "please face", "overthinking", "calm breathing", "sudden idea",
    ],
    "daily": [
        "brushing teeth", "checking phone", "carrying groceries", "watering plant",
        "looking for keys", "making tea", "cleaning table", "doing laundry",
        "opening fridge", "waiting in line", "packing backpack", "fixing a cable",
        "wearing slippers", "holding umbrella", "reading receipt", "lost in hallway",
        "tiny shopping bag", "charging phone", "late for bus", "laundry basket",
    ],
    "food_sleep": [
        "hugging pizza slice", "stealing cheese", "tea mug blanket", "midnight snack",
        "sleep mask", "pillow fort", "coffee survival", "cookie crumbs",
        "instant noodles", "toast celebration", "breakfast chaos", "soup comfort",
        "fridge raid", "snoring cloud", "blanket burrito", "cake slice stare",
        "tiny sandwich", "cereal bowl", "sleepy yawn", "tea ceremony",
    ],
    "work_study": [
        "laptop focus", "deadline panic", "notebook planning", "video call face",
        "spreadsheet despair", "pen behind ear", "coffee meeting", "printer jam",
        "sticky notes", "presentation pose", "exam stress", "book tower",
        "headphones mode", "calendar reminder", "office chair spin", "code review stare",
        "tiny clipboard", "late homework", "big calculator", "marker board",
    ],
    "weather_seasons": [
        "sunny sunglasses", "raincoat puddle", "windy scarf", "snow hat",
        "spring flowers", "autumn leaf pile", "summer fan", "winter cocoa",
        "storm blanket", "foggy morning", "heatwave melt", "first snow",
        "tiny snowman", "leaf umbrella", "rainy window", "cold nose",
        "beach towel", "muddy boots", "cloud watching", "seasonal scarf",
    ],
    "cozy_love": [
        "heart hands", "warm hug", "family photo", "gift box",
        "tiny bouquet", "thank you bow", "supportive thumbs up", "comfort blanket",
        "movie night", "soft lamp", "shared tea", "kind note",
        "cozy socks", "gentle smile", "tiny postcard", "candle evening",
        "birthday cupcake", "care package", "home sweet pose", "sleepy cuddle",
    ],
    "adventures": [
        "space helmet", "tiny backpack", "treasure map", "paper boat",
        "magnifying glass", "cardboard car", "moon flag", "forest walk",
        "tiny superhero cape", "bug explorer", "campfire cocoa", "mountain peek",
        "toy airplane", "pirate hat", "submarine window", "kite chase",
        "compass confusion", "road trip snack", "secret tunnel", "star gazing",
    ],
    "reactions": [
        "yes boss", "no way", "what now", "okay fine",
        "facepalm", "side eye", "big applause", "mic drop",
        "bravo pose", "stop sign", "go on", "wait what",
        "deal with it", "not today", "too much", "send help",
        "approved", "suspicious", "big mood", "instant regret",
    ],
    "chaos": [
        "falling papers", "spilled tea", "running in circles", "burnt toast",
        "chair tip", "sock mystery", "wrong button", "forgot why",
        "tiny explosion pose", "bag disaster", "calendar collapse", "wifi panic",
        "messy room", "alarm scream", "door stuck", "confetti accident",
        "cable tangle", "laundry avalanche", "kitchen smoke", "panic dance",
    ],
    "daily_fail": [
        "missed alarm", "wrong door", "forgot umbrella", "empty wallet",
        "dropped snack", "inside-out shirt", "lost remote", "late message",
        "burned dinner", "phone at one percent", "no clean cup", "shoe mismatch",
        "forgot password", "tiny traffic jam", "bad hair", "wrong chat",
        "failed high five", "flat soda", "cold coffee", "wet socks",
    ],
    "office_study_fail": [
        "camera on by accident", "mute panic", "forgot attachment", "typo disaster",
        "meeting overload", "blank slide", "exam blank mind", "ink spill",
        "tab overload", "forgot deadline", "coffee on notes", "printer betrayal",
        "broken pencil", "keyboard smash", "group project pain", "wrong file",
        "calendar ambush", "forgot formula", "paper pile", "brain loading",
    ],
    "food_sleep_absurd": [
        "arguing with cookie", "sleeping in cup", "pizza crown", "spoon sword",
        "noodle scarf", "toast shield", "fridge worship", "pillow throne",
        "blanket cave", "dreaming cheese", "coffee IV joke", "cereal flood",
        "sandwich helmet", "soup hot tub", "cake hypnosis", "tea whirlpool",
        "snack mountain", "sleepy levitation", "fork drama", "yawn portal",
    ],
    "weird_original": [
        "tiny detective noir", "cosmic laundry", "philosophy cheese", "haunted toaster",
        "wizard receipt", "time-travel slippers", "dramatic houseplant", "moon elevator",
        "invisible bicycle", "bureaucratic dragon toy", "mini thundercloud", "pocket universe",
        "sentient teacup", "keyboard oracle", "sock parliament", "fridge portal",
        "quantum snack", "calendar monster", "umbrella duel", "tiny opera",
    ],
    "cozy": [
        "reading under blanket", "warm cocoa", "knitted scarf", "tiny fireplace",
        "soft pillow", "window rain", "sleepy lamp", "tea steam",
        "book nook", "cozy chair", "warm socks", "gentle sunrise",
        "blanket nest", "small candle", "quiet music", "soft pajamas",
        "tiny lantern", "comfort soup", "slow morning", "peaceful nap",
    ],
    "tiny_heroics": [
        "lifting huge button", "saving cookie", "holding tiny shield", "rescuing sock",
        "brave umbrella", "hero cape", "standing on mug", "defeating dust",
        "protecting cupcake", "climbing book", "helping friend", "tiny medal",
        "opening big door", "fixing wire", "guarding tea", "carrying star",
        "facing alarm clock", "heroic broom", "holding flag", "victory sparkle",
    ],
    "grumpy_reactions": [
        "grumpy yes", "grumpy no", "judging stare", "arms crossed",
        "spines raised", "not impressed", "tiny rage", "silent protest",
        "dramatic sigh", "leave me alone", "slow blink", "annoyed tea",
        "skeptical eyebrow", "mood cloud", "hard pass", "stern nod",
        "why though", "tiny complaint", "fed up", "serious business",
    ],
    "everyday_fails": [
        "stuck in scarf", "dropped keys", "umbrella flip", "shopping bag tear",
        "burned toast", "lost glove", "soap bubble panic", "slipper trip",
        "missed bus", "wrong sweater", "laundry static", "phone drop",
        "plant overwater", "messy table", "blanket trap", "doorbell panic",
        "spilled soup", "dust sneeze", "wet floor", "bag too heavy",
    ],
    "social_moods": [
        "awkward hello", "shy wave", "party corner", "too many people",
        "friend hug", "message typing", "left on read", "group photo",
        "small talk panic", "birthday wish", "apology bow", "thankful smile",
        "introvert recharge", "confetti shy", "phone call dread", "secret handshake",
        "invite accepted", "invite declined", "social battery low", "warm welcome",
    ],
    "friendship": [
        "sharing tea", "holding hands", "team high five", "umbrella together",
        "movie blanket", "shared snack", "map planning", "comfort hug",
        "gift exchange", "walking side by side", "helping climb", "tiny picnic",
        "joint victory", "listening friend", "matching scarves", "cozy couch",
        "birthday surprise", "small promise", "teamwork broom", "safe home",
    ],
    "family": [
        "family dinner", "photo frame", "home hug", "chores together",
        "grocery team", "tea evening", "blanket pile", "birthday candle",
        "home repair", "kind reminder", "movie night", "tiny garden",
        "family walk", "care note", "shared umbrella", "pancake morning",
        "bedtime story", "small celebration", "kitchen helper", "welcome home",
    ],
    "helping": [
        "lifting box", "fixing lamp", "cleaning spill", "carrying bag",
        "finding keys", "holding ladder", "sharing charger", "tying scarf",
        "rescuing snack", "repairing mug", "team cooking", "pushing cart",
        "sweeping floor", "packing lunch", "watering plant", "opening jar",
        "saving note", "untangling cable", "holding door", "team checklist",
    ],
    "tiny_adventures": [
        "cardboard spaceship", "paper boat trip", "forest path", "blanket mountain",
        "book cave", "kitchen expedition", "toy train", "moon postcard",
        "compass debate", "rain puddle voyage", "secret map", "window stars",
        "camping mug", "desk safari", "button treasure", "chair mountain",
        "paper plane", "backpack quest", "snow trail", "cookie island",
    ],
    "arguments": [
        "remote control debate", "last cookie fight", "blanket territory", "who broke cup",
        "direction argument", "tiny courtroom", "dramatic pointing", "silent treatment",
        "snack negotiation", "laundry blame", "map disagreement", "queue dispute",
        "too loud complaint", "tea temperature debate", "whose turn", "doorbell blame",
        "pillow border", "calendar conflict", "dramatic exit", "make up hug",
    ],
    "chaos_team": [
        "two-person panic", "running with papers", "wrong lever", "kitchen alarm",
        "shopping cart race", "umbrella spin", "desk collapse", "confetti mess",
        "cable knot", "bag spill", "toast emergency", "laundry storm",
        "toy car crash", "weather panic", "fridge raid", "calendar attack",
        "printer cloud", "soup rescue", "chair chase", "button overload",
    ],
    "roommate_life": [
        "dish debate", "shared fridge", "rent calendar", "laundry schedule",
        "late night snack", "sofa ownership", "quiet hours", "lost remote",
        "plant duty", "trash reminder", "movie choice", "blanket theft",
        "coffee queue", "door sign", "tiny vacuum", "shared charger",
        "fridge note", "cleaning day", "wifi reset", "peace treaty",
    ],
    "mutual_panic": [
        "deadline together", "alarm together", "storm together", "phone low battery",
        "wrong train", "message seen", "forgot gift", "guest arriving",
        "burning toast", "lost tickets", "calendar surprise", "sudden noise",
        "bug on table", "rain started", "file missing", "doorbell",
        "budget math", "exam tomorrow", "meeting now", "delivery arrived",
    ],
    "weird_duo": [
        "cosmic teapot", "two tiny wizards", "receipt prophecy", "sock courtroom",
        "moon elevator", "fridge portal", "dramatic spoon", "haunted calendar",
        "opera argument", "invisible umbrella", "cloud pet", "keyboard ritual",
        "time-travel snack", "floating couch", "laundry galaxy", "button kingdom",
        "teacup submarine", "pocket thunder", "philosophy toast", "tiny parade",
    ],
    "app_core_reactions": [
        "like", "love", "thanks", "sorry",
        "ok", "wow", "done", "later",
        "wait", "help", "good morning", "good night",
        "congrats", "miss you", "busy", "on my way",
        "agree", "disagree", "hug", "celebrate",
    ],
    "daily_moods": [
        "morning energy", "evening tired", "weekend joy", "monday face",
        "productive mode", "lazy mode", "cleaning mood", "shopping mood",
        "quiet mood", "social mood", "hungry mood", "sleepy mood",
        "focused mood", "lost mood", "cozy mood", "party mood",
        "rainy mood", "sunny mood", "tiny victory", "small defeat",
    ],
    "celebrations": [
        "birthday", "new year", "first snow", "weekend",
        "payday", "finished task", "good news", "tiny trophy",
        "confetti", "gift", "cake", "sparkler",
        "family day", "cozy holiday", "snow globe", "summer picnic",
        "movie night", "home party", "work win", "small miracle",
    ],
    "love_family": [
        "warm hug", "heart gift", "home comfort", "miss you",
        "call me", "take care", "family tea", "gentle support",
        "small bouquet", "thank you", "kind note", "safe trip",
        "welcome home", "proud of you", "sleep well", "cheer up",
        "together", "for you", "soft apology", "happy home",
    ],
    "excuses": [
        "five more minutes", "traffic in kitchen", "phone died", "forgot but stylish",
        "almost done", "internet fell", "brain unavailable", "calendar lied",
        "tea emergency", "laundry incident", "snack delay", "very important nap",
        "wrong universe", "chair trapped me", "spines malfunction", "tail problem",
        "tiny crisis", "paperwork fog", "weather excuse", "loading personality",
    ],
    "panic": [
        "everything at once", "alarm face", "message storm", "deadline siren",
        "lost file", "guest at door", "forgot name", "battery one percent",
        "sudden meeting", "too many tabs", "kettle scream", "bag missing",
        "rain no umbrella", "gift forgotten", "wrong chat", "calendar attack",
        "delivery here", "exam now", "printer smoke", "brain reboot",
    ],
    "internet_brain": [
        "too many tabs", "doomscroll spiral", "buffering face", "typing typing",
        "sent too soon", "wrong emoji", "screenshot panic", "notification flood",
        "low battery", "charger hunt", "wifi dance", "muted microphone",
        "camera surprise", "scrolling in bed", "lost password", "captcha rage",
        "group chat chaos", "sticker reply", "download stuck", "algorithm stare",
    ],
    "household_chaos": [
        "laundry mountain", "dishes tower", "dust bunny hunt", "vacuum duel",
        "fridge empty", "trash day", "plant drama", "sock missing",
        "table clutter", "cup collection", "blanket thief", "tiny broom",
        "mop slip", "soap spill", "grocery avalanche", "remote lost",
        "window cleaning", "bed sheet fight", "kitchen timer", "closet surprise",
    ],
    "monday_energy": [
        "coffee before words", "alarm betrayal", "blank stare", "late start",
        "work bag drag", "calendar dread", "bus sprint", "shirt wrinkle",
        "slow boot", "meeting face", "desk nap", "email flood",
        "lunch countdown", "tiny resilience", "second coffee", "after work relief",
        "monday crown", "task pile", "printer queue", "survival pose",
    ],
    "suspicious": [
        "side eye", "magnifying glass", "tiny detective", "sniff test",
        "who did this", "raised eyebrow", "checking receipt", "listening wall",
        "mystery crumb", "door peek", "evidence bag", "not convinced",
        "hmm pose", "secret note", "shadow watch", "tea interrogation",
        "trap question", "silent stare", "case closed", "still suspicious",
    ],
    "surreal": [
        "floating mug", "tiny moon couch", "calendar ocean", "spoon portal",
        "cloud shoes", "pocket galaxy", "talking toast", "mirror wink",
        "umbrella indoors", "fridge nebula", "teacup planet", "sock eclipse",
        "keyboard mountain", "staircase loop", "lamp sunrise", "paper rain",
        "cosmic blanket", "tiny thunder", "impossible chair", "dream receipt",
    ],
}


@dataclass(frozen=True)
class Pack:
    group: str
    style: str
    category: str
    grid_count: int


PACKS = [
    Pack("rats", "plush_3d", "emotions", 4),
    Pack("rats", "plush_3d", "daily", 4),
    Pack("rats", "plush_3d", "food_sleep", 3),
    Pack("rats", "plush_3d", "work_study", 3),
    Pack("rats", "plush_3d", "weather_seasons", 2),
    Pack("rats", "plush_3d", "cozy_love", 2),
    Pack("rats", "plush_3d", "adventures", 2),
    Pack("rats", "meme_wobbly", "reactions", 5),
    Pack("rats", "meme_wobbly", "chaos", 5),
    Pack("rats", "meme_wobbly", "daily_fail", 4),
    Pack("rats", "meme_wobbly", "office_study_fail", 3),
    Pack("rats", "meme_wobbly", "food_sleep_absurd", 2),
    Pack("rats", "meme_wobbly", "weird_original", 1),
    Pack("hedgehogs", "plush_3d", "cozy", 4),
    Pack("hedgehogs", "plush_3d", "emotions", 3),
    Pack("hedgehogs", "plush_3d", "daily", 3),
    Pack("hedgehogs", "plush_3d", "weather_seasons", 2),
    Pack("hedgehogs", "plush_3d", "food_sleep", 2),
    Pack("hedgehogs", "plush_3d", "tiny_heroics", 1),
    Pack("hedgehogs", "meme_wobbly", "grumpy_reactions", 4),
    Pack("hedgehogs", "meme_wobbly", "chaos", 3),
    Pack("hedgehogs", "meme_wobbly", "everyday_fails", 3),
    Pack("hedgehogs", "meme_wobbly", "food_sleep_absurd", 2),
    Pack("hedgehogs", "meme_wobbly", "social_moods", 2),
    Pack("hedgehogs", "meme_wobbly", "weird_original", 1),
    Pack("duos", "plush_3d", "friendship", 1),
    Pack("duos", "plush_3d", "family", 1),
    Pack("duos", "plush_3d", "helping", 1),
    Pack("duos", "plush_3d", "cozy", 1),
    Pack("duos", "plush_3d", "tiny_adventures", 1),
    Pack("duos", "meme_wobbly", "arguments", 1),
    Pack("duos", "meme_wobbly", "chaos_team", 1),
    Pack("duos", "meme_wobbly", "roommate_life", 1),
    Pack("duos", "meme_wobbly", "mutual_panic", 1),
    Pack("duos", "meme_wobbly", "weird_duo", 1),
    Pack("mixed", "plush_3d", "app_core_reactions", 2),
    Pack("mixed", "plush_3d", "daily_moods", 2),
    Pack("mixed", "plush_3d", "weather_seasons", 2),
    Pack("mixed", "plush_3d", "celebrations", 2),
    Pack("mixed", "plush_3d", "love_family", 2),
    Pack("mixed", "meme_wobbly", "app_core_reactions", 2),
    Pack("mixed", "meme_wobbly", "excuses", 2),
    Pack("mixed", "meme_wobbly", "panic", 1),
    Pack("mixed", "meme_wobbly", "internet_brain", 1),
    Pack("mixed", "meme_wobbly", "household_chaos", 1),
    Pack("mixed", "meme_wobbly", "monday_energy", 1),
    Pack("mixed", "meme_wobbly", "suspicious", 1),
    Pack("mixed", "meme_wobbly", "surreal", 1),
]


def make_global_signature(global_index: int) -> str:
    color = ACCENT_COLORS[global_index % len(ACCENT_COLORS)]
    detail = ACCENT_DETAILS[(global_index // len(ACCENT_COLORS)) % len(ACCENT_DETAILS)]
    cycle = global_index // (len(ACCENT_COLORS) * len(ACCENT_DETAILS))
    if cycle:
        return f"{color} {detail}, extra asymmetrical placement variant {cycle + 1}"
    return f"{color} {detail}"


def select_concepts(category: str, offset: int, global_start_index: int) -> list[str]:
    concepts = CONCEPT_POOLS[category]
    items = []
    used = set()
    for index in range(GRID_SIZE):
        base_index = ((offset * GRID_SIZE) + index) % len(concepts)
        base = concepts[base_index]
        concept = base
        if concept in used:
            for shift in range(1, len(concepts) + 1):
                partner = concepts[(base_index + shift + offset) % len(concepts)]
                concept = f"{base} combined with {partner}"
                if concept not in used:
                    break
        if concept in used:
            raise RuntimeError(f"Could not build a unique concept for {category}")

        used.add(concept)
        direction = CELL_DIRECTIONS[(offset + index) % len(CELL_DIRECTIONS)]
        signature = make_global_signature(global_start_index + index)
        items.append(
            f"cell {index + 1:02d}: {concept}, {direction}, "
            f"unique visible accent: {signature}"
        )
    return items


def make_grid_prompt(pack: Pack, grid_index: int, concepts: list[str]) -> str:
    character = CHARACTER_DESCRIPTIONS[pack.group]
    style = STYLE_DESCRIPTIONS[pack.style]
    concept_text = "; ".join(concepts)
    return (
        "Create a clean 5x5 sticker sheet with 25 separate mobile app stickers. "
        "Use a perfectly flat solid #00ff00 chroma-key background with no shadows, "
        "gradients, textures, floor plane, labels, logos, or watermark. "
        f"Characters: {character}. "
        f"Style: {style}. "
        f"Theme: {pack.category.replace('_', ' ')} batch {grid_index:03d}. "
        f"Each cell must contain one complete centered sticker with generous padding. "
        "All 25 stickers must be visually unique: no repeated pose, prop set, facial "
        "expression, silhouette, or composition inside the same grid. "
        "Do not create twins, copy-paste characters, mirrored duplicates, or the same "
        "character with only a tiny color change. "
        f"Use these 25 unique design briefs in row-major order: {concept_text}. "
        "No readable text inside the artwork. Keep silhouettes bold, funny, and easy "
        "to understand at small mobile size. Avoid green elements because the green "
        "background will be removed later."
    )


def build_catalog() -> tuple[list[dict], list[dict], list[dict]]:
    pack_plan = []
    grid_prompts = []
    stickers = []
    global_sticker_index = 0

    for pack in PACKS:
        source_dir = SOURCE_DIR / pack.group / pack.style / pack.category
        output_dir = LIBRARY_DIR / pack.group / pack.style / pack.category
        source_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)
        (source_dir / ".gitkeep").touch()
        (output_dir / ".gitkeep").touch()

        pack_id = f"{pack.group}_{pack.style}_{pack.category}"
        pack_plan.append(
            {
                "pack_id": pack_id,
                "group": pack.group,
                "style": pack.style,
                "category": pack.category,
                "prompt_version": PROMPT_VERSION,
                "grid_count": pack.grid_count,
                "sticker_count": pack.grid_count * GRID_SIZE,
                "source_dir": str(source_dir.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "output_dir": str(output_dir.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            }
        )

        for grid_number in range(1, pack.grid_count + 1):
            grid_global_start = global_sticker_index
            concepts = select_concepts(pack.category, grid_number - 1, grid_global_start)
            grid_id = f"{pack_id}_grid_{grid_number:03d}"
            source_path = source_dir / f"{grid_id}_v{PROMPT_VERSION}.png"
            source_exists = source_path.exists()
            grid_prompts.append(
                {
                    "grid_id": grid_id,
                    "pack_id": pack_id,
                    "prompt_version": PROMPT_VERSION,
                    "group": pack.group,
                    "style": pack.style,
                    "category": pack.category,
                    "count": GRID_SIZE,
                    "source_path": str(source_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                    "source_exists": source_exists,
                    "output_dir": str(output_dir.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                    "prompt": make_grid_prompt(pack, grid_number, concepts),
                }
            )

            for cell_number, concept in enumerate(concepts, start=1):
                sticker_index = ((grid_number - 1) * GRID_SIZE) + cell_number
                sticker_id = f"{pack_id}_{sticker_index:03d}"
                output_path = output_dir / f"{sticker_id}.png"
                stickers.append(
                    {
                        "id": sticker_id,
                        "status": "ready" if source_exists and output_path.exists() else "planned",
                        "group": pack.group,
                        "style": pack.style,
                        "category": pack.category,
                        "grid_id": grid_id,
                        "cell": cell_number,
                        "concept": concept,
                        "tags": [pack.group, pack.style, pack.category],
                        "path": str(output_path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                    }
                )
                global_sticker_index += 1

    return pack_plan, grid_prompts, stickers


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    CATALOG_DIR.mkdir(parents=True, exist_ok=True)
    pack_plan, grid_prompts, stickers = build_catalog()
    target_count = sum(item["sticker_count"] for item in pack_plan)

    write_json(
        CATALOG_DIR / "pack_plan.json",
        {
            "schema_version": 1,
            "prompt_version": PROMPT_VERSION,
            "target_count": target_count,
            "grid_size": GRID_SIZE,
            "styles": STYLE_DESCRIPTIONS,
            "packs": pack_plan,
        },
    )

    with (CATALOG_DIR / "grid_prompts.jsonl").open("w", encoding="utf-8", newline="\n") as stream:
        for item in grid_prompts:
            stream.write(json.dumps(item, ensure_ascii=False) + "\n")

    write_json(
        STICKER_ROOT / "manifest.json",
        {
            "schema_version": 1,
            "prompt_version": PROMPT_VERSION,
            "target_count": target_count,
            "grid_count": len(grid_prompts),
            "sticker_count": len(stickers),
            "source": "generated_grid_plan",
            "stickers": stickers,
        },
    )

    print(f"Sticker catalog ready: {target_count} stickers, {len(grid_prompts)} grids")


if __name__ == "__main__":
    main()
