import 'package:cotool/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the blog shell and tool entry', (tester) async {
    await tester.pumpWidget(const IconForgeApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('成长历程1996'), findsOneWidget);
    expect(find.text('文章归档'), findsWidgets);
    expect(find.text('图标工具'), findsOneWidget);
    expect(find.text('JSON 转 Dart'), findsOneWidget);
    expect(find.text('文件转换'), findsOneWidget);
    expect(find.text('局域网传输'), findsOneWidget);
  });
}
