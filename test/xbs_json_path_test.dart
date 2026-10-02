import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/protocol/book_source_protocol.dart';
import 'package:xxread/book_sources/xbs/xbs_json_path.dart';

void main() {
  test('recursive search filters keep matching groups and nested fields', () {
    final data = {
      'data': {
        'state': [
          {'dataID': 100, 'title': 'Advertisement'},
          {
            'dataID': 360,
            'items': [
              {'title': 'Book one', 'docId': '9_42'},
            ],
          },
          {
            'dataID': 360,
            'items': [
              {'title': 'Book two', 'docId': '9_43'},
            ],
          },
          {'dataID': '360', 'title': 'Different type'},
        ],
      },
    };
    final groups =
        XbsJsonPath.select(data, r'$..state[?(@.dataID==360)]', nodes: true)
            as List;
    expect(groups, hasLength(2));
    expect(XbsJsonPath.select(groups.first, r'$..title'), 'Book one');
    expect(XbsJsonPath.select(groups.last, r'$..docId'), '9_43');
    expect(XbsJsonPath.select(data, r'$.state', nodes: true), isEmpty);
  });

  test('recursive arrays do not duplicate descendants or flatten early', () {
    final data = {
      'groups': [
        {
          'pageList': [1, 2],
        },
        {
          'pageList': [3],
        },
      ],
    };
    expect(XbsJsonPath.select(data, r'$..pageList[*]'), [1, 2, 3]);
    expect(XbsJsonPath.select(data, r'$..pageList[0]'), [1, 3]);
    expect(XbsJsonPath.select(data, 'groups/1/pageList/0'), 3);
    expect(XbsJsonPath.select(data, r'$.groups[9]', nodes: true), isEmpty);
  });

  test('filters support property existence and literal comparisons', () {
    final data = {
      'rows': [
        {'kind': 'book', 'children': []},
        {'kind': 'audio', 'children': null},
        {'kind': 'book'},
      ],
    };
    expect(
      XbsJsonPath.select(data, r'$..[?(@.children)]', nodes: true),
      hasLength(2),
    );
    expect(
      XbsJsonPath.select(data, r'''$.rows[?(@.kind=='book')]''', nodes: true),
      hasLength(2),
    );
    expect(
      XbsJsonPath.select(data, r'$.rows[?(@.kind!="audio")]', nodes: true),
      hasLength(2),
    );
    expect(
      XbsJsonPath.select(
        {
          'a.b': [7],
        },
        r'''$['a.b'][0]''',
      ),
      7,
    );
  });

  test('unsupported filters fail explicitly instead of executing script', () {
    for (final path in [
      r'$.rows[?(@.id > 1)]',
      r'$.rows[?(@.id==evil())]',
      r'$.rows[',
    ]) {
      expect(
        () => XbsJsonPath.select({'rows': []}, path),
        throwsA(isA<BookSourceProtocolException>()),
      );
    }
  });
}
