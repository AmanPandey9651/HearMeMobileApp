import 'package:flutter/material.dart';

typedef SendGameSignal = Future<void> Function(Map<String, dynamic> payload);

class InCallMiniGames extends StatefulWidget {
  final bool isCaller;
  final ValueNotifier<Map<String, dynamic>?> incomingSignal;
  final SendGameSignal send;

  const InCallMiniGames({
    super.key,
    required this.isCaller,
    required this.incomingSignal,
    required this.send,
  });

  @override
  State<InCallMiniGames> createState() => _InCallMiniGamesState();
}

class _InCallMiniGamesState extends State<InCallMiniGames> with SingleTickerProviderStateMixin {
  static const wyrCards = <({String a, String b})>[
    (a: 'Be able to read minds at will', b: 'Be able to teleport anywhere instantly'),
    (a: 'Live without internet for 1 full year', b: 'Live without music for 3 full years'),
    (a: 'Always speak your honest mind with zero filter', b: 'Never be able to speak unless spoken to first'),
    (a: 'Have the ability to restart your life from age 10', b: 'Receive ₹5,000,000 in cash right now'),
    (a: 'Never feel physical fatigue again', b: 'Never feel emotional heartbreak again'),
    (a: 'Be trapped in a luxury elevator with an ex', b: 'Be trapped in a dark elevator with a complete stranger'),
    (a: 'Have 1 absolute best friend for life', b: 'Have 100 casual acquaintances who always invite you out'),
  ];

  late final TabController tabs;
  final board = List<String?>.filled(9, null);
  String currentTurn = 'X';
  String? winner;
  String get mySymbol => widget.isCaller ? 'X' : 'O';

  int wyrIndex = 0;
  String? myChoice;
  String? peerChoice;

  int questionCount = 0;
  final questions = <_Question>[];
  final questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    tabs.addListener(() {
      if (!tabs.indexIsChanging) {
        final game = ['TTT', 'WYR', '20Q'][tabs.index];
        widget.send({'game': game, 'action': 'OPEN', 'data': <String, dynamic>{}});
      }
    });
    widget.incomingSignal.addListener(_receive);
    WidgetsBinding.instance.addPostFrameCallback((_) => _receive());
  }

  @override
  void dispose() {
    widget.incomingSignal.removeListener(_receive);
    questionController.dispose();
    tabs.dispose();
    super.dispose();
  }

  void _receive() {
    final signal = widget.incomingSignal.value;
    if (signal == null || !mounted) return;
    final game = '${signal['game'] ?? ''}';
    final action = '${signal['action'] ?? ''}';
    final data = signal['data'] is Map ? Map<String, dynamic>.from(signal['data'] as Map) : <String, dynamic>{};
    final targetTab = game == 'WYR' ? 1 : game == '20Q' ? 2 : 0;
    if (tabs.index != targetTab) tabs.animateTo(targetTab);

    setState(() {
      if (game == 'TTT') {
        if (action == 'MOVE') {
          final index = (data['index'] as num?)?.toInt() ?? -1;
          final symbol = '${data['symbol'] ?? ''}';
          if (index >= 0 && index < board.length && (symbol == 'X' || symbol == 'O')) {
            board[index] = symbol;
            currentTurn = symbol == 'X' ? 'O' : 'X';
            _checkWinner();
          }
        } else if (action == 'RESET') {
          _resetTtt(broadcast: false);
        }
      } else if (game == 'WYR') {
        if (action == 'CHOICE') {
          final c = '${data['choice'] ?? ''}';
          if (c == 'A' || c == 'B') peerChoice = c;
        } else if (action == 'NEXT') {
          wyrIndex = ((data['index'] as num?)?.toInt() ?? 0).clamp(0, wyrCards.length - 1).toInt();
          myChoice = null;
          peerChoice = null;
        }
      } else if (game == '20Q') {
        if (action == 'ASK') {
          final text = '${data['text'] ?? ''}'.trim();
          if (text.isNotEmpty) questions.add(_Question(text));
          questionCount = (data['count'] as num?)?.toInt() ?? questions.length;
        } else if (action == 'ANSWER' && questions.isNotEmpty) {
          questions.last.answer = '${data['answer'] ?? ''}';
        } else if (action == 'RESET') {
          questionCount = 0;
          questions.clear();
        }
      }
    });
  }

  void _checkWinner() {
    const lines = <List<int>>[
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final line in lines) {
      final a = board[line[0]];
      if (a != null && a == board[line[1]] && a == board[line[2]]) {
        winner = a;
        return;
      }
    }
    if (board.every((e) => e != null)) winner = 'DRAW';
  }

  Future<void> _playCell(int index) async {
    if (board[index] != null || winner != null || currentTurn != mySymbol) return;
    setState(() {
      board[index] = mySymbol;
      currentTurn = mySymbol == 'X' ? 'O' : 'X';
      _checkWinner();
    });
    await widget.send({'game': 'TTT', 'action': 'MOVE', 'data': {'index': index, 'symbol': mySymbol}});
  }

  void _resetTtt({bool broadcast = true}) {
    for (var i = 0; i < board.length; i++) board[i] = null;
    currentTurn = 'X';
    winner = null;
    if (broadcast) widget.send({'game': 'TTT', 'action': 'RESET', 'data': <String, dynamic>{}});
  }

  Future<void> _chooseWyr(String choice) async {
    setState(() => myChoice = choice);
    await widget.send({'game': 'WYR', 'action': 'CHOICE', 'data': {'choice': choice}});
  }

  Future<void> _nextWyr() async {
    final next = (wyrIndex + 1) % wyrCards.length;
    setState(() {
      wyrIndex = next;
      myChoice = null;
      peerChoice = null;
    });
    await widget.send({'game': 'WYR', 'action': 'NEXT', 'data': {'index': next}});
  }

  Future<void> _ask() async {
    if (questionCount >= 20) return;
    final text = questionController.text.trim();
    if (text.isEmpty) return;
    final count = questionCount + 1;
    questionController.clear();
    setState(() {
      questionCount = count;
      questions.add(_Question(text));
    });
    await widget.send({'game': '20Q', 'action': 'ASK', 'data': {'text': text, 'count': count}});
  }

  Future<void> _answer(String answer) async {
    if (questions.isEmpty) return;
    setState(() => questions.last.answer = answer);
    await widget.send({'game': '20Q', 'action': 'ANSWER', 'data': {'answer': answer}});
  }

  Future<void> _reset20q() async {
    setState(() {
      questionCount = 0;
      questions.clear();
    });
    await widget.send({'game': '20Q', 'action': 'RESET', 'data': <String, dynamic>{}});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .82,
        child: Column(
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.sports_esports)),
              title: const Text('In-call mini-games', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Synced live with the other participant'),
              trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ),
            TabBar(controller: tabs, tabs: const [Tab(text: 'Tic-Tac-Toe'), Tab(text: 'Would You Rather'), Tab(text: '20 Questions')]),
            Expanded(
              child: TabBarView(
                controller: tabs,
                children: [_ttt(), _wyr(), _twentyQuestions()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ttt() {
    final status = winner == 'DRAW'
        ? 'Draw — good game!'
        : winner != null
            ? (winner == mySymbol ? 'You won! 🏆' : 'Peer won this round')
            : currentTurn == mySymbol
                ? 'Your turn ($mySymbol)'
                : 'Waiting for peer ($currentTurn)';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(status, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
              itemCount: 9,
              itemBuilder: (_, i) => FilledButton.tonal(
                onPressed: () => _playCell(i),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text(board[i] ?? '', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: OutlinedButton.icon(onPressed: () => setState(() => _resetTtt()), icon: const Icon(Icons.refresh), label: const Text('New round'))),
      ],
    );
  }

  Widget _wyr() {
    final card = wyrCards[wyrIndex];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(children: [Expanded(child: Text('Card ${wyrIndex + 1} of ${wyrCards.length}', style: const TextStyle(fontWeight: FontWeight.bold))), TextButton.icon(onPressed: _nextWyr, icon: const Icon(Icons.refresh), label: const Text('Next'))]),
        const SizedBox(height: 8),
        _choice('A', card.a),
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Center(child: Text('— OR —'))),
        _choice('B', card.b),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(child: Text('You: ${myChoice == null ? 'Thinking…' : 'Option $myChoice'}')),
                Expanded(child: Text('Peer: ${peerChoice == null ? 'Waiting…' : 'Option $peerChoice'}')),
              ],
            ),
          ),
        ),
        if (myChoice != null && peerChoice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(myChoice == peerChoice ? '✨ Great minds think alike! You matched!' : '⚡ Different perspectives!', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _choice(String choice, String text) => FilledButton.tonal(
        onPressed: () => _chooseWyr(choice),
        style: FilledButton.styleFrom(padding: const EdgeInsets.all(18), alignment: Alignment.centerLeft),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('OPTION $choice', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(text)]),
      );

  Widget _twentyQuestions() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [Expanded(child: Text('Question $questionCount of 20', style: const TextStyle(fontWeight: FontWeight.bold))), TextButton(onPressed: _reset20q, child: const Text('Reset'))]),
        ),
        Expanded(
          child: questions.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('One player thinks of a person, place, or thing. The other can ask up to 20 Yes/No questions.', textAlign: TextAlign.center)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: questions.length,
                  itemBuilder: (_, i) {
                    final q = questions[i];
                    final latestUnanswered = i == questions.length - 1 && q.answer == null;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Q${i + 1}: ${q.text}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (q.answer != null) Align(alignment: Alignment.centerRight, child: Chip(label: Text(q.answer!))),
                          if (latestUnanswered)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 6, children: ['YES', 'NO', 'MAYBE'].map((a) => OutlinedButton(onPressed: () => _answer(a), child: Text(a))).toList()),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (questionCount < 20)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [Expanded(child: TextField(controller: questionController, onSubmitted: (_) => _ask(), decoration: const InputDecoration(hintText: 'Type a Yes/No question…'))), const SizedBox(width: 8), IconButton.filled(onPressed: _ask, icon: const Icon(Icons.send))]),
            ),
          ),
      ],
    );
  }
}

class _Question {
  final String text;
  String? answer;
  _Question(this.text, [this.answer]);
}
