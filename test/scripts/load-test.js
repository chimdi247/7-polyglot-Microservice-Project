// Load test: steady, realistic traffic across all 7 services -- the
// baseline "does this behave correctly under normal load" check, run
// before stress-test.js or spike-test.js.
//
// Run via ../load-test.sh, or directly:
//   k6 run load-test.js
import { sleep } from 'k6';
import { browseAllServices } from './helpers.js';

export const options = {
  scenarios: {
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '2m', target: 20 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800', 'p(99)<1500'],
  },
};

export default function () {
  browseAllServices();
  sleep(1);
}
