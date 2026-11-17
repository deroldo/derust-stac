import 'package:stac_core/stac_core.dart';

// `recoveryOutcome` reports the result of the recovery that is running (it is
// meant for the `recover` actions of a server error envelope). Outside a
// recovery it is logged and ignored, so this button is a harmless demo.
@StacScreen(screenName: 'recovery_outcome')
StacWidget recoveryOutcomeExample() {
  return StacScaffold(
    appBar: StacAppBar(title: StacText(data: 'Recovery Outcome')),
    body: StacCenter(
      child: StacColumn(
        mainAxisAlignment: StacMainAxisAlignment.center,
        children: [
          StacText(data: 'Reports success, failure or unavailable'),
          StacSizedBox(height: 16),
          StacElevatedButton(
            onPressed: StacAction(
              jsonData: {'actionType': 'recoveryOutcome', 'result': 'failure'},
            ),
            child: StacText(data: 'Emit failure'),
          ),
        ],
      ),
    ),
  );
}
