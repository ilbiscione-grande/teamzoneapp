part of '../../app/teamzone_app.dart';

/// A principle ready to be added to a team's game model, from a template,
/// the guide or the standard list. The text is Swedish team content that the
/// leader changes freely once added.
///
/// The content is a draft until someone with coaching expertise has reviewed
/// it (see docs/implementation/tdp-redesign.md).
class _TdpIdea {
  const _TdpIdea(this.area, this.title, this.description);
  final PrincipleArea area;
  final String title, description;
}

/// A ready game model to start from.
class _TdpTemplate {
  const _TdpTemplate({
    required this.key,
    required this.name,
    required this.nameEn,
    required this.summary,
    required this.summaryEn,
    required this.ideas,
  });
  final String key, name, nameEn, summary, summaryEn;
  final List<_TdpIdea> ideas;
}

/// A question of the guide: each answer brings its principles.
class _TdpQuestion {
  const _TdpQuestion(this.key, this.question, this.questionEn, this.answers);
  final String key, question, questionEn;
  final List<(String, String, List<_TdpIdea>)> answers;
}

// A broad base: one principle in each phase.
const _tdpScoreWhenOpen = _TdpIdea(
  PrincipleArea.scoring,
  'Avsluta när läget finns',
  'Vi tar chansen att skjuta när vi har yta och vinkel. Hellre ett avslut för '
      'mycket än en passning för mycket i straffområdet.',
);
const _tdpPlayable = _TdpIdea(
  PrincipleArea.buildUp,
  'Skapa spelbarhet',
  'Spelarna rör sig så att bollhållaren alltid har ett kort och ett långt '
      'passningsalternativ.',
);
const _tdpForwardFirst = _TdpIdea(
  PrincipleArea.counter,
  'Spela framåt direkt',
  'När vi vinner bollen letar vi först efter en passning eller löpning framåt.',
);
const _tdpWidthDepth = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Bredd och djup',
  'Vi använder hela planens bredd och har alltid någon som hotar på djupet.',
);
const _tdpDisturbShooter = _TdpIdea(
  PrincipleArea.preventingScoring,
  'Stör skytten',
  'Närmaste spelare pressar den som ska avsluta och blockerar skottet.',
);
const _tdpSteer = _TdpIdea(
  PrincipleArea.preventingBuildUp,
  'Styr motståndarens spel',
  'Vi styr bollhållaren mot kanten, där vi lättare kan vinna bollen.',
);
const _tdpReact = _TdpIdea(
  PrincipleArea.regaining,
  'Reagera direkt',
  'När vi tappar bollen pressar närmaste spelare inom några sekunder.',
);
const _tdpCompact = _TdpIdea(
  PrincipleArea.defending,
  'Kompakt lag',
  'Vi håller kort avstånd mellan lagdelarna och skyddar ytan framför mål.',
);

// Keeping the ball.
const _tdpShortFromKeeper = _TdpIdea(
  PrincipleArea.buildUp,
  'Kort uppbyggnad från målvakten',
  'Målvakten spelar kort till mittbackarna, som breddar sig. Mittfältarna '
      'kommer ned och erbjuder sig.',
);
const _tdpAroundPress = _TdpIdea(
  PrincipleArea.buildUp,
  'Spela runt pressen',
  'Hittar vi ingen väg framåt spelar vi tillbaka eller över till andra sidan '
      'och börjar om.',
);
const _tdpTriangles = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Trianglar och vinklar',
  'Spelarna runt bollen bildar trianglar, så att bollhållaren alltid har två '
      'passningsalternativ.',
);
const _tdpPatience = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Tålamod med bollen',
  'Vi behåller bollen tills en lucka öppnar sig i stället för att forcera '
      'framåt.',
);
const _tdpIntoBox = _TdpIdea(
  PrincipleArea.scoring,
  'Spela in i straffområdet',
  'Vi spelar oss in i straffområdet med passningar och inspel längs marken.',
);
const _tdpSecureFirst = _TdpIdea(
  PrincipleArea.counter,
  'Säkra bollen först',
  'Efter bollvinst spelar vi en säker första passning, om det inte finns ett '
      'tydligt läge framåt.',
);
const _tdpHighCompact = _TdpIdea(
  PrincipleArea.defending,
  'Högt och kompakt',
  'Laget flyttar upp tillsammans och håller kort avstånd mellan lagdelarna.',
);
const _tdpCloseMiddle = _TdpIdea(
  PrincipleArea.preventingBuildUp,
  'Stäng mitten',
  'Vi stänger passningarna centralt och tvingar motståndaren ut mot kanterna.',
);
const _tdpGuardGoal = _TdpIdea(
  PrincipleArea.preventingScoring,
  'Skydda ytan framför mål',
  'Försvararna står mellan bollen och mål och blockerar avslut.',
);

// Winning the ball and going quickly.
const _tdpLowBlock = _TdpIdea(
  PrincipleArea.defending,
  'Lågt och kompakt block',
  'Vi försvarar på egen planhalva med kort avstånd mellan spelarna och '
      'stänger mitten.',
);
const _tdpHarmlessBall = _TdpIdea(
  PrincipleArea.preventingBuildUp,
  'Låt dem ha bollen ofarligt',
  'Motståndaren får ha bollen långt från vårt mål. Vi pressar först när '
      'bollen kommer in på vår planhalva.',
);
const _tdpWinInZone = _TdpIdea(
  PrincipleArea.regaining,
  'Vinn bollen i vår zon',
  'Vi dubblar på bollhållaren när bollen spelas in där vi vill vinna den.',
);
const _tdpQuickForward = _TdpIdea(
  PrincipleArea.counter,
  'Snabbt framåt efter bollvinst',
  'Första passningen går framåt om det går, och två eller tre spelare '
      'springer direkt mot mål.',
);
const _tdpRunsInDepth = _TdpIdea(
  PrincipleArea.counter,
  'Löpningar i djupled',
  'Forwards och yttrar löper bakom backlinjen så fort vi vinner bollen.',
);
const _tdpFewTouches = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Få tillslag mot mål',
  'Vi tar oss mot mål på få passningar och använder ytorna innan '
      'motståndaren hunnit hem.',
);
const _tdpShootEarly = _TdpIdea(
  PrincipleArea.scoring,
  'Avsluta tidigt',
  'Vi avslutar tidigt i anfallet, innan försvaret har hunnit organisera sig.',
);
const _tdpDirect = _TdpIdea(
  PrincipleArea.buildUp,
  'Direkt spel när det behövs',
  'Under press spelar målvakten och backarna långt mot en forward eller en '
      'löpning.',
);
const _tdpManyInBox = _TdpIdea(
  PrincipleArea.preventingScoring,
  'Många i straffområdet',
  'Vid inlägg och avslut är vi många i straffområdet och rensar bort bollen.',
);

// Pressing high.
const _tdpPressHigh = _TdpIdea(
  PrincipleArea.preventingBuildUp,
  'Pressa högt',
  'Vi pressar motståndarens backar och målvakt redan på deras planhalva.',
);
const _tdpPressSignals = _TdpIdea(
  PrincipleArea.preventingBuildUp,
  'Pressa tillsammans på signal',
  'Laget pressar samtidigt på en signal, till exempel en dålig touch eller en '
      'passning bakåt.',
);
const _tdpFiveSeconds = _TdpIdea(
  PrincipleArea.regaining,
  'Jaga bollen direkt efter bolltapp',
  'Alla nära bollen jagar den direkt, innan motståndaren hinner vända upp.',
);
const _tdpHighLine = _TdpIdea(
  PrincipleArea.defending,
  'Hög backlinje',
  'Backlinjen flyttar upp så att laget hålls kort bakom pressen.',
);
const _tdpStrikeHigh = _TdpIdea(
  PrincipleArea.counter,
  'Avgör efter bollvinst högt',
  'Vinner vi bollen högt spelar vi snabbt mot mål medan försvaret är '
      'oorganiserat.',
);
const _tdpCloseFinish = _TdpIdea(
  PrincipleArea.scoring,
  'Avsluta på få touchar',
  'Efter en bollvinst nära mål söker vi avslut direkt.',
);
const _tdpPacedBuild = _TdpIdea(
  PrincipleArea.buildUp,
  'Uppbyggnad med fart',
  'Vi spelar framåt snabbt i uppbyggnaden för att komma upp och pressa igen.',
);
const _tdpNearBall = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Många nära bollen',
  'Vi anfaller med många spelare nära bollen, så att vi kan pressa direkt om '
      'den tappas.',
);
const _tdpSweeperKeeper = _TdpIdea(
  PrincipleArea.preventingScoring,
  'Målvakten bakom backlinjen',
  'Målvakten står högt och tar hand om bollar som spelas bakom backlinjen.',
);

// Only in the guide.
const _tdpCrosses = _TdpIdea(
  PrincipleArea.scoring,
  'Inlägg och närspel',
  'Vi tar oss till kanten och slår inlägg, och är minst två i straffområdet.',
);
const _tdpWingPlay = _TdpIdea(
  PrincipleArea.attackingPlay,
  'Kantspel',
  'Vi söker oss ut mot kanterna och skapar två mot en där.',
);
const _tdpRetreat = _TdpIdea(
  PrincipleArea.regaining,
  'Falla hem tillsammans',
  'Tappar vi bollen långt fram springer alla hem och organiserar oss innan vi '
      'pressar.',
);

const _tdpTemplates = [
  _TdpTemplate(
    key: 'base',
    name: 'Grund i alla spelfaser',
    nameEn: 'A base in every phase',
    summary:
        'En princip i varje skede. Bra att börja med om ni inte har bestämt '
        'en spelstil.',
    summaryEn:
        'One principle in each phase. A good start if you have not chosen a '
        'style.',
    ideas: [
      _tdpScoreWhenOpen,
      _tdpPlayable,
      _tdpForwardFirst,
      _tdpWidthDepth,
      _tdpDisturbShooter,
      _tdpSteer,
      _tdpReact,
      _tdpCompact,
    ],
  ),
  _TdpTemplate(
    key: 'possession',
    name: 'Bollinnehav',
    nameEn: 'Possession',
    summary: 'Laget vill ha bollen, bygger upp kort och anfaller med tålamod.',
    summaryEn:
        'The team wants the ball, builds up short and attacks patiently.',
    ideas: [
      _tdpShortFromKeeper,
      _tdpAroundPress,
      _tdpTriangles,
      _tdpPatience,
      _tdpIntoBox,
      _tdpSecureFirst,
      _tdpReact,
      _tdpHighCompact,
      _tdpCloseMiddle,
      _tdpGuardGoal,
    ],
  ),
  _TdpTemplate(
    key: 'counter',
    name: 'Omställningar',
    nameEn: 'Counter-attacks',
    summary:
        'Laget försvarar kompakt och anfaller snabbt när bollen är vunnen.',
    summaryEn:
        'The team defends compactly and attacks fast once the ball is won.',
    ideas: [
      _tdpLowBlock,
      _tdpHarmlessBall,
      _tdpWinInZone,
      _tdpQuickForward,
      _tdpRunsInDepth,
      _tdpFewTouches,
      _tdpShootEarly,
      _tdpDirect,
      _tdpManyInBox,
    ],
  ),
  _TdpTemplate(
    key: 'press',
    name: 'Högt presspel',
    nameEn: 'High press',
    summary:
        'Laget pressar högt, vinner bollen nära motståndarens mål och avgör '
        'snabbt.',
    summaryEn:
        'The team presses high, wins the ball near the opponent\'s goal and '
        'finishes fast.',
    ideas: [
      _tdpPressHigh,
      _tdpPressSignals,
      _tdpFiveSeconds,
      _tdpHighLine,
      _tdpStrikeHigh,
      _tdpCloseFinish,
      _tdpPacedBuild,
      _tdpNearBall,
      _tdpSweeperKeeper,
    ],
  ),
];

/// The principles a block can pick from when the team has written none.
List<_TdpIdea> get _tdpStandardIdeas => _tdpTemplates.first.ideas;

/// The guide: a question per phase, rules from answers to principles.
const _tdpQuestions = [
  _TdpQuestion(
    'build_up',
    'Hur vill ni bygga upp spelet från målvakten?',
    'How do you want to build up from the goalkeeper?',
    [
      ('Kort, med passningar', 'Short, with passes', [_tdpShortFromKeeper]),
      ('Långt, mot forwards', 'Long, towards the forwards', [_tdpDirect]),
      ('Efter läge', 'Depending on the situation', [_tdpPlayable]),
    ],
  ),
  _TdpQuestion(
    'attacking_play',
    'Hur vill ni anfalla?',
    'How do you want to attack?',
    [
      (
        'Med tålamod och många passningar',
        'Patiently, with many passes',
        [_tdpTriangles, _tdpPatience],
      ),
      ('Snabbt, på få passningar', 'Fast, with few passes', [_tdpFewTouches]),
      ('Brett, via kanterna', 'Wide, through the flanks', [_tdpWingPlay]),
    ],
  ),
  _TdpQuestion(
    'scoring',
    'Hur skapar ni målchanser?',
    'How do you create chances?',
    [
      ('Spelar in i straffområdet', 'Passing into the box', [_tdpIntoBox]),
      ('Avslutar tidigt', 'Shooting early', [_tdpShootEarly]),
      ('Med inlägg', 'With crosses', [_tdpCrosses]),
    ],
  ),
  _TdpQuestion(
    'counter',
    'Vad gör ni när ni vinner bollen?',
    'What do you do when you win the ball?',
    [
      (
        'Spelar framåt direkt',
        'Play forward at once',
        [_tdpQuickForward, _tdpRunsInDepth],
      ),
      ('Säkrar bollen först', 'Secure the ball first', [_tdpSecureFirst]),
    ],
  ),
  _TdpQuestion(
    'regaining',
    'Vad gör ni när ni tappar bollen?',
    'What do you do when you lose the ball?',
    [
      ('Pressar direkt', 'Press at once', [_tdpFiveSeconds]),
      (
        'Faller hem och organiserar oss',
        'Drop back and get organised',
        [_tdpRetreat],
      ),
    ],
  ),
  _TdpQuestion(
    'defending',
    'Var på planen vill ni försvara?',
    'Where on the pitch do you want to defend?',
    [
      (
        'Högt, på deras planhalva',
        'High, in their half',
        [_tdpPressHigh, _tdpHighLine],
      ),
      ('På mitten', 'In the middle', [_tdpSteer, _tdpCompact]),
      (
        'Lågt, nära eget mål',
        'Low, near our own goal',
        [_tdpHarmlessBall, _tdpLowBlock],
      ),
    ],
  ),
  _TdpQuestion(
    'preventing_scoring',
    'Hur försvarar ni straffområdet?',
    'How do you defend the box?',
    [
      ('Stör den som ska skjuta', 'Disturb the shooter', [_tdpDisturbShooter]),
      ('Är många och rensar', 'Many players who clear', [_tdpManyInBox]),
    ],
  ),
];
