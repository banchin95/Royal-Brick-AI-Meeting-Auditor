Map<String, dynamic> apiFixture() => {
  'source': 'openai',
  'model': 'test-model',
  'score': {'earned': 4, 'available': 8, 'normalized': 50, 'coverage': 8},
  'stages': List.generate(
    9,
    (i) => {
      'status': i == 0 ? 'scored' : 'no_data',
      'points': i == 0 ? 4 : null,
      'comment': i == 0 ? 'Контакт установлен.' : 'Нет данных для оценки.',
    },
  ),
  'price': {
    'checks': List.filled(5, 'no_data'),
    'sequence': 'недостаточно данных',
    'comment': 'Цена не обсуждается в фрагменте.',
  },
  'sections': List.generate(
    13,
    (i) => {
      'body': i == 1
          ? 'Оценён только контакт.'
          : 'Нет данных для этого раздела.',
      'evidence': i == 0
          ? [
              {'at': null, 'speaker': 1, 'text': 'Здравствуйте!'},
            ]
          : [],
    },
  ),
};
