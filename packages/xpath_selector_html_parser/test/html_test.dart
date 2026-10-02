import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';
import 'package:xpath_selector/xpath_selector.dart';
import 'package:xpath_selector/src/utils/dom_selector.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

final String htmlString = '''
<html lang="en">
<body>
<div><a href='https://github.com/simonkimi'>author</a></div>
<div class="head">div head</div>
<div class="container">
    <table>
        <tbody>
          <tr>
              <td id="td1" class="first1">1</td>
              <td id="td2" class="first1">2</td>
              <td id="td3" class="first2">3</td>
              <td id="td4" class="first2 form">4</td>

              <td id="td5" class="second1">one</td>
              <td id="td6" class="second1">two</td>
              <td id="td7" class="second2">three</td>
              <td id="td8" class="second2">four</td>
          </tr>
        </tbody>
    </table>
</div>
<div class="end">end</div>
</body>
</html>
''';

final html = parse(htmlString).documentElement!;

extension TestTransfer on Element {
  XPathNode? query(String selector) =>
      HtmlNodeTree.from(querySelector(selector));

  List<XPathNode> queryAll(String selector) =>
      querySelectorAll(selector).map((e) => HtmlNodeTree(e)).toList();
}

void main() {
  test('attribute presence and indexed text retain XPath context', () {
    final doc = HtmlXPath.html(
      '<div id="a"><p class="">first<b>nested</b>second</p>'
      '<p>third<i>skip</i>fourth</p><p data-x="a|b/c">last</p></div>',
    );
    expect(doc.query('//p[@class]').nodes.length, 1);
    expect(doc.query('//p[not(@class)]').nodes.length, 2);
    expect(doc.query('//p[not(@*)]').nodes.length, 1);
    expect(doc.query('//p[@class or @data-x]').nodes.length, 2);
    expect(doc.query('//p/text()[2]').attrs, ['second', 'fourth']);
    expect(doc.query('//p/text()').attrs, [
      'first',
      'second',
      'third',
      'fourth',
      'last',
    ]);
    expect(
      doc.query('//p [position()>1] [position()<last()]/text()[1]').attrs,
      ['third'],
    );
    expect(doc.query('//p[@data-x="a|b/c"]/text()').attrs, ['last']);
    expect(doc.query('//b/../text()[1]').attrs, ['first']);
  });
  test(
    'count and last predicates select full catalogs without return links',
    () {
      final tree = HtmlXPath.html(
        '<main><ul><li>A</li><li>B</li><li>C</li></ul>'
        '<ul><li>Recommendation</li></ul><div><p>A</p><p>B</p>'
        '<p class="title">Return</p></div></main>',
      );
      expect(tree.query('//ul[count(li)>1]/li').nodes.map((n) => n.text), [
        'A',
        'B',
        'C',
      ]);
      expect(
        tree.query('//ul[count(*)>=3 and count(li)!=0]/li').nodes,
        hasLength(3),
      );
      expect(
        tree.query('//div/p[position()<last()]').nodes.map((n) => n.text),
        ['A', 'B'],
      );
      expect(
        tree.query('//div/p[position()=last()]').nodes.single.text,
        'Return',
      );
      expect(tree.query('//div/p[position()<=2]').nodes.map((n) => n.text), [
        'A',
        'B',
      ]);
      expect(
        tree.query('//div/p[not(@class="title")]').nodes.map((n) => n.text),
        ['A', 'B'],
      );
      expect(
        tree
            .query('//div/p[not(contains(@class,"title"))]')
            .nodes
            .map((n) => n.text),
        ['A', 'B'],
      );
    },
  );

  test('XBS wildcard attribute predicates preserve node-set comparison', () {
    final tree = HtmlXPath.html(
      '<main><div id="other" class="sortList">A</div>'
      '<div data-kind="sortList">B</div><div>C</div></main>',
    );
    expect(tree.query('//*[@*="sortList"]').nodes.map((node) => node.text), [
      'A',
      'B',
    ]);
    expect(
      tree.query('//div[not(@*="sortList")]').nodes.map((node) => node.text),
      ['C'],
    );
    expect(tree.query('//div[@*!="sortList"]').nodes.map((node) => node.text), [
      'A',
    ]);
  });

  test('XBS current-node text works in contains and equality', () {
    final tree = HtmlXPath.html(
      '<main><a>正文<span>内容</span></a><a>广告</a></main>',
    );
    expect(tree.query('//a[contains(., "正文")]').nodes.single.text, '正文内容');
    expect(tree.query('//a[not(contains(., "广告"))]').nodes.single.text, '正文内容');
    expect(tree.query('//a[.="广告"]').nodes.single.text, '广告');
  });

  test('basic', () {
    expect(html.queryXPath('//div/a').node, html.query('a'));
    expect(
      html.queryXPath('//div/a/@href').attr,
      html.query('a')!.attributes['href'],
    );
    expect(
      html.queryXPath('//td[@id="td1"]/@*').attrs,
      html.query('#td1')!.attributes.values,
    );
    expect(html.queryXPath('//div/a/text()').attr, html.query('a')!.text);
    expect(html.queryXPath('//tr/node()').nodes, html.query('tr')!.children);
    expect(
      html.queryXPath('//tr/td[@class^="fir" and not(text()="4")]').nodes,
      [html.query('#td1'), html.query('#td2'), html.query('#td3')],
    );
  });

  test('simple predicate', () {
    expect(html.queryXPath('//tr/td[1]').node, html.query('#td1'));
    expect(html.queryXPath('//tr/td[last()]').node, html.query('#td8'));
    expect(html.queryXPath('//tr/td[last()-1]').node, html.query('#td7'));
    expect(html.queryXPath('//tr/td[position()<3]').nodes, [
      html.query('#td1'),
      html.query('#td2'),
    ]);
    expect(html.queryXPath('//tr/td[position() < 3]').nodes, [
      html.query('#td1'),
      html.query('#td2'),
    ]);
  });

  test('complex predicate', () {
    expect(
      html.queryXPath('//tr/td[position() >= 2 and @class="second1"]').nodes,
      [html.query('#td5'), html.query('#td6')],
    );
    expect(
      html.queryXPath('//tr/td[position() >= 2 and position() < 4]').nodes,
      [html.query('#td2'), html.query('#td3')],
    );
    expect(
      html.queryXPath('//tr/td[position() <= 1 or position() >= 8]').nodes,
      [html.query('#td1'), html.query('#td8')],
    );
  });

  test('extend predicate', () {
    expect(
      html.queryXPath('//tr/td[@class="first1"]').nodes,
      html.queryAll('td[class="first1"]'),
    );
    expect(
      html.queryXPath('//tr/td[@class^="fir"]').nodes,
      html.queryAll('td[class^="fir"]'),
    );
    expect(
      html.queryXPath('//tr/td[@class~="form"]').nodes,
      html.queryAll('td[class~="form"]'),
    );
    expect(
      html.queryXPath(r'//tr/td[@class$="1"]').nodes,
      html.queryAll(r'td[class$="1"]'),
    );
  });

  test('combination query', () {
    expect(html.queryXPath('//div/a|//div[@class="head"]').nodes, [
      html.query('a'),
      html.query('.head'),
    ]);
    expect(html.queryXPath('//div/a | //div[@class="head"]').nodes, [
      html.query('a'),
      html.query('.head'),
    ]);
  });

  test('axes', () {
    expect(
      html.queryXPath('//td[@id="td1"]/attribute::class').attr,
      html.query('#td1')!.attributes['class'],
    );
    expect(
      html.queryXPath('//td[@id="td1"]/attribute::*').attrs,
      html.query('#td1')!.attributes.values,
    );
    expect(html.queryXPath('//td/parent::*').node, html.query('tr'));
    expect(html.queryXPath('//tr/child::*').nodes, html.queryAll('td'));
    expect(
      html.queryXPath('//td/ancestor::*').nodes,
      ancestor(html.query('td')),
    );
    expect(
      html.queryXPath('//tr/ancestor-or-self::*').nodes,
      ancestorOrSelf(html.query('tr')),
    );
    expect(
      html.queryXPath('//table/descendant::td').nodes,
      html.queryAll('td'),
    );
    expect(html.queryXPath('//table//tbody/descendant-or-self::*').nodes, [
      html.query('tbody'),
      html.query('tr'),
      ...html.queryAll('td'),
    ]);
  });

  test('function', () {
    expect(
      html.queryXPath('//td[contains(@class, "first")]').nodes,
      html.queryAll('td[class^="first"]'),
    );
    expect(
      html.queryXPath('//td[not(contains(@class, "first"))]').nodes,
      html.queryAll('td[class^="second"]'),
    );
    expect(
      html.queryXPath('//td[contains(text(), "one")]').nodes,
      html.queryAll('#td5'),
    );
    expect(
      html.queryXPath('//td[starts-with(text(), "o")]').nodes,
      html.queryAll('#td5'),
    );
    expect(html.queryXPath('//td[ends-with(text(), "e")]').nodes, [
      html.query('#td5'),
      html.query('#td7'),
    ]);
    expect(
      html.queryXPath('//td[contains(@class, "first") and text() = "3"]').nodes,
      html.queryAll('#td3'),
    );
  });

  test('multi predicate', () {
    expect(
      html.queryXPath('//td[@class^="second"][2]').nodes,
      html.queryAll('#td6'),
    );
  });
}
