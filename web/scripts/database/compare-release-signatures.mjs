import {isDeepStrictEqual} from 'node:util';

// pg_dump deparses BETWEEN into a nested AND; restore's SQL parser flattens it.
// Accept only these exact known forms of the deployed, pure built-in conjunction.
export const weekdaysNested = '(private,provider_work_schedules,provider_work_schedules_weekdays_check,"CHECK ((((cardinality(weekdays) >= 1) AND (cardinality(weekdays) <= 7)) AND (weekdays <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint])))")';
export const weekdaysFlat = '(private,provider_work_schedules,provider_work_schedules_weekdays_check,"CHECK (((cardinality(weekdays) >= 1) AND (cardinality(weekdays) <= 7) AND (weekdays <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint, (6)::smallint, (7)::smallint])))")';
export function compareReleaseSignatures(a,b){
 const canonical=x=>({...x,constraints:x.constraints.map(row=>row===weekdaysNested?weekdaysFlat:row)});
 return isDeepStrictEqual(canonical(a),canonical(b));
}
