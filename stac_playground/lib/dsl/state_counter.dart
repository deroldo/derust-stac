import 'package:stac_core/stac_core.dart';

// Widgets that read state (`visible`, `enabled`, bindings) and the screen
// `state` block are written as raw maps with `StacWidget(jsonData: ...)`;
// `StacBinding` builds the `$state` / `$expr` values.
@StacScreen(screenName: 'state_counter')
StacWidget stateCounterExample() {
  return StacWidget(
    jsonData: {
      'type': 'scaffold',
      'state': {'total': 0},
      'appBar': StacAppBar(title: StacText(data: 'State counter')),
      'body': StacCenter(
        child: StacColumn(
          mainAxisAlignment: StacMainAxisAlignment.center,
          children: [
            StacWidget(
              jsonData: {
                'type': 'text',
                'data': StacBinding.expr("'Total: ' + total"),
              },
            ),
            StacSizedBox(height: 8),
            StacWidget(
              jsonData: {
                'type': 'text',
                'data': 'Limit reached',
                'visible': StacBinding.expr('total >= 10'),
              },
            ),
            StacSizedBox(height: 16),
            StacRow(
              mainAxisAlignment: StacMainAxisAlignment.center,
              children: [
                StacWidget(
                  jsonData: {
                    'type': 'elevatedButton',
                    'enabled': StacBinding.expr('total > 0'),
                    'child': StacText(data: '-'),
                    'onPressed': StacAction(
                      jsonData: {
                        'actionType': 'decrementState',
                        'key': 'total',
                        'min': 0,
                      },
                    ),
                  },
                ),
                StacSizedBox(width: 16),
                StacWidget(
                  jsonData: {
                    'type': 'elevatedButton',
                    'enabled': StacBinding.expr('total < 10'),
                    'child': StacText(data: '+'),
                    'onPressed': StacAction(
                      jsonData: {
                        'actionType': 'incrementState',
                        'key': 'total',
                        'max': 10,
                      },
                    ),
                  },
                ),
              ],
            ),
            StacSizedBox(height: 16),
            StacTextButton(
              child: StacText(data: 'Reset'),
              onPressed: StacAction(jsonData: {'actionType': 'resetState'}),
            ),
          ],
        ),
      ),
    },
  );
}
