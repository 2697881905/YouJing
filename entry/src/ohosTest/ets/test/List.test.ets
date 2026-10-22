import abilityTest from './Ability.test';
import tripParserTest from './TripParser.test';
import dataSeederTest from './DataSeeder.test';

export default function testsuite() {
  abilityTest();
  tripParserTest();
  dataSeederTest();
}
