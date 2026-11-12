import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_framework/stac_framework.dart';

class StacCancelRequestParser extends StacActionParser<StacCancelRequest> {
  const StacCancelRequestParser();

  @override
  String get actionType => ActionType.cancelRequest.name;

  @override
  StacCancelRequest getModel(Map<String, dynamic> json) =>
      StacCancelRequest.fromJson(json);

  @override
  FutureOr<dynamic> onCall(BuildContext context, StacCancelRequest model) {
    StacStateScope.requestsOf(context).cancel(model.requestKey);
    return null;
  }
}
