// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

import '../../../parse.dart';
import '../../../visitor/interface/expression.dart';
import '../expression.dart';
import '../argument_invocation.dart';
import '../callable_invocation.dart';

class IfExpression implements Expression, CallableInvocation {
  static final declaration =
      parseArgumentDeclaration(r"($condition, $if-true, $if-false)");

  final ArgumentInvocation arguments;

  final FileSpan span;

  IfExpression(this.arguments, this.span);

  /*=T*/ accept/*<T>*/(ExpressionVisitor/*<T>*/ visitor) =>
      visitor.visitIfExpression(this);

  String toString() => "if$arguments";
}