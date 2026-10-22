import abilityTest from './Ability.test';
import tripParserTest from './TripParser.test';
import dataSeederTest from './DataSeeder.test';
import llmPipelineTest from './LlmPipeline.test';
import accountTest from './Account.test';

export default function testsuite() {
  abilityTest();
  tripParserTest();
  dataSeederTest();
  llmPipelineTest();
  accountTest();
}
