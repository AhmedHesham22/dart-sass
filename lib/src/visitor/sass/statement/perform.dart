// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import '../../../ast/css/node.dart';
import '../../../ast/sass/expression.dart';
import '../../../ast/sass/statement.dart';
import '../../../ast/selector.dart';
import '../../../environment.dart';
import '../../../parser.dart';
import '../../../value.dart';
import '../expression/perform.dart';
import '../statement.dart';

class PerformVisitor extends StatementVisitor {
  final Environment _environment;
  final PerformExpressionVisitor _expressionVisitor;

  /// The current selector, if any.
  CssValue<SelectorList> _selector;

  /// The current media queries, if any.
  List<CssMediaQuery> _mediaQueries;

  /// The root stylesheet node.
  CssStylesheet _root;

  /// The current parent node in the output CSS tree.
  CssParentNode _parent;
  
  PerformVisitor() : this._(new Environment());

  PerformVisitor._(Environment environment)
      : _environment = environment,
        _expressionVisitor = new PerformExpressionVisitor(environment);

  void visit(Statement node) => node.accept(this);

  CssStylesheet visitStylesheet(Stylesheet node) {
    _root = new CssStylesheet(span: node.span);
    _parent = _root;
    super.visitStylesheet(node);
    return _root;
  }

  void visitComment(Comment node) {
    if (node.isSilent) return;
    _addChild(new CssComment(node.text, span: node.span));
  }

  void visitDeclaration(Declaration node) {
    var name = _performInterpolation(node.name);
    var cssValue = _performExpression(node.value);
    var value = cssValue.value;

    // Don't abort for an empty list because converting it to CSS will throw an
    // error that we want to user to see.
    if (value.isBlank &&
        !(value is SassList && value.contents.isEmpty)) {
      return;
    }

    _addChild(new CssDeclaration(name, cssValue, span: node.span));
  }

  void visitAtRule(AtRule node) {
    var value = node.value == null
        ? null
        : _performInterpolation(node.value, trim: true);

    if (node.children == null) {
      _addChild(new CssAtRule(node.name, value: value, span: node.span));
    }

    _withParent(
        new CssAtRule(node.name, value: value, span: node.span),
        () => super.visitAtRule(node),
        through: (node) => node is CssStyleRule);
  }

  void visitMediaRule(MediaRule node) {
    var queryIterable = node.queries.map(_visitMediaQuery);
    var queries = _mediaQueries == null
        ? new List<CssMediaQuery>.unmodifiable(queryIterable)
        : _mergeMediaQueries(_mediaQueries, queryIterable);
    if (queries.isEmpty) return;

    _withParent(
        new CssMediaRule(queries, span: node.span),
        () => _withMediaQueries(queries, () => super.visitMediaRule(node)),
        through: (node) => node is CssStyleRule || node is CssMediaRule,
        removeIfEmpty: true);
  }

  List<CssMediaQuery> _mergeMediaQueries(
      Iterable<CssMediaQuery> queries1, Iterable<CssMediaQuery> queries2) {
    return new List.unmodifiable(queries1.expand/*<CssMediaQuery>*/((query1) {
      return queries2.map((query2) => query1.merge(query2));
    }).where((query) => query != null));
  }

  CssMediaQuery _visitMediaQuery(MediaQuery query) {
    var modifier = query.modifier == null
        ? null
        : _performInterpolation(query.modifier);

    var type = query.type == null
        ? null
        : _performInterpolation(query.type);

    var features = query.features
        .map((feature) => _performInterpolation(feature));

    if (type == null) return new CssMediaQuery.condition(features);
    return new CssMediaQuery(type, modifier: modifier, features: features);
  }

  void visitStyleRule(StyleRule node) {
    var selectorText = _performInterpolation(node.selector, trim: true);
    if (_selector != null) {
      // TODO: semantically resolve parent references.
      selectorText = new CssValue(
          "${_selector.value} ${selectorText.value}",
          span: node.selector.span);
    }

    // TODO: catch errors and re-contextualize them relative to
    // [node.selector.span.start].
    var selector = new CssValue<SelectorList>(
        new Parser(selectorText.value).parseSelector(),
        span: node.selector.span);

    _withParent(
        new CssStyleRule(selector, span: node.span),
        () => _withSelector(selector, () => super.visitStyleRule(node)),
        through: (node) => node is CssStyleRule,
        removeIfEmpty: true);
  }

  void visitVariableDeclaration(VariableDeclaration node) {
    _environment.setVariable(
        node.name, node.expression.accept(_expressionVisitor),
        global: node.isGlobal);
  }

  CssValue<String> _performInterpolation(
      InterpolationExpression interpolation, {bool trim: false}) {
    var result = _expressionVisitor.visitInterpolationExpression(interpolation)
        .text;
    return new CssValue(trim ? result.trim() : result);
  }

  CssValue<Value> _performExpression(Expression expression) =>
      new CssValue(expression.accept(_expressionVisitor));

  void _addChild(CssNode node) {
    _parent.addChild(node);
  }

  /*=T*/ _withParent/*<S extends CssParentNode, T>*/(
      /*=S*/ node, /*=T*/ callback(),
      {bool through(CssNode node), bool removeIfEmpty: false}) {
    var oldParent = _parent;

    // Go up through parents that match [through].
    var parent = _parent;
    if (through != null) {
      while (through(parent)) {
        parent = parent.parent;
      }
    }

    parent.addChild(node);
    _parent = node;
    var result = _environment.scope(callback);
    if (removeIfEmpty && node.children.isEmpty) node.remove();
    _parent = oldParent;

    return result;
  }

  /*=T*/ _withSelector/*<T>*/(CssValue<SelectorList> selector,
      /*=T*/ callback()) {
    var oldSelector = _selector;
    _selector = selector;
    var result = callback();
    _selector = oldSelector;
    return result;
  }

  /*=T*/ _withMediaQueries/*<T>*/(List<CssMediaQuery> queries,
      /*=T*/ callback()) {
    var oldMediaQueries = _mediaQueries;
    _mediaQueries = queries;
    var result = callback();
    _mediaQueries = oldMediaQueries;
    return result;
  }
}