const unlabelledText =
    'Мне нужны панели для дома. Какая площадь? Примерно 40 квадратных метров.';
const preparedText =
    'Участник 1: Мне нужны панели для дома.\n\n'
    'Участник 2: Какая площадь?\n\nУчастник 1: Примерно 40 квадратных метров.';

Map<String, dynamic> preparationFixture({bool unknownManager = false}) => {
  'source': 'ai',
  'model': 'test-model',
  'transcript': preparedText,
  'notice': 'Проверьте предположения по записи.',
  'inferred_turns': true,
  'participants': [
    {
      'speaker': 1,
      'role': 'client',
      'confidence': 'high',
      'reason': 'Описывает свой объект.',
      'evidence': 'Мне нужны панели для дома.',
    },
    {
      'speaker': 2,
      'role': unknownManager ? 'unknown' : 'manager',
      'confidence': unknownManager ? 'low' : 'medium',
      'reason': 'Выясняет объём работ.',
      'evidence': 'Какая площадь?',
    },
  ],
};
