// Spike test: a sudden, massive burst of traffic followed by an
// equally sudden drop -- checks the polyglot stack survives the burst
// and recovers cleanly once it passes, rather than staying degraded.
//
// Run via ../spike-test.sh, or directly:
//   k6 run spike-test.js
import { sleep } from 'k6';
import { browseAllServices } from './helpers.js';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '10s', target: 400 },
        { duration: '1m', target: 400 },
        { duration: '10s', target: 10 },
        { duration: '1m', target: 10 },
        { duration: '20s', target: 0 },
      ],
      gracefulRampDown: '15s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.5'],
  },
};

export default function () {
  browseAllServices();
  sleep(0.1);
}
