import tripParserTest from './TripParser.test';
import dataSeederTest from './DataSeeder.test';
import llmPipelineTest from './LlmPipeline.test';
import accountTest from './Account.test';
import todayPlanTest from './TodayPlan.test';
import icsBuilderTest from './IcsBuilder.test';
import failureCopyTest from './FailureCopy.test';
import geoTest from './Geo.test';
import mapStopsTest from './MapStops.test';
import todayCardTest from './TodayCard.test';
import styleConfigTest from './StyleConfig.test';
import transitSymbolTest from './TransitSymbol.test';
import planDraftTest from './PlanDraft.test';
import promptContractTest from './PromptContract.test';
import skipPlannerTest from './SkipPlanner.test';
import replanParserTest from './ReplanParser.test';
import responsiveTest from './Responsive.test';
import displayTextTest from './DisplayText.test';

export default function testsuite() {
  tripParserTest();
  dataSeederTest();
  llmPipelineTest();
  accountTest();
  todayPlanTest();
  icsBuilderTest();
  failureCopyTest();
  geoTest();
  mapStopsTest();
  todayCardTest();
  styleConfigTest();
  transitSymbolTest();
  planDraftTest();
  promptContractTest();
  skipPlannerTest();
  replanParserTest();
  responsiveTest();
    displayTextTest();
}
