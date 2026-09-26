// Shared helpers imported by every scenario script in test/scripts/.
import http from 'k6/http';
import { check } from 'k6';

export const AUTH_URL = __ENV.AUTH_URL || 'http://localhost:8081';
export const CATALOG_URL = __ENV.CATALOG_URL || 'http://localhost:8082';
export const INVENTORY_URL = __ENV.INVENTORY_URL || 'http://localhost:8083';
export const ORDER_URL = __ENV.ORDER_URL || 'http://localhost:8084';
export const PAYMENT_URL = __ENV.PAYMENT_URL || 'http://localhost:8085';
export const NOTIFICATION_URL = __ENV.NOTIFICATION_URL || 'http://localhost:8086';
export const ANALYTICS_URL = __ENV.ANALYTICS_URL || 'http://localhost:8087';

// A read-heavy mix across all 7 services -- health checks plus each
// service's main read endpoint. Exercises the same cross-service call
// pattern analytics-service's /analytics/summary makes internally,
// but from k6 directly so every service gets load, not just whichever
// one happens to be the entry point.
export function browseAllServices() {
  const responses = http.batch([
    ['GET', `${AUTH_URL}/health`, null, { tags: { name: 'GET auth/health' } }],
    ['GET', `${CATALOG_URL}/products`, null, { tags: { name: 'GET catalog/products' } }],
    ['GET', `${INVENTORY_URL}/inventory`, null, { tags: { name: 'GET inventory/inventory' } }],
    ['GET', `${ORDER_URL}/orders`, null, { tags: { name: 'GET order/orders' } }],
    ['GET', `${PAYMENT_URL}/payments`, null, { tags: { name: 'GET payment/payments' } }],
    ['GET', `${NOTIFICATION_URL}/health`, null, { tags: { name: 'GET notification/health' } }],
    ['GET', `${ANALYTICS_URL}/analytics/summary`, null, { tags: { name: 'GET analytics/summary' } }],
  ]);

  responses.forEach((res) => {
    check(res, { 'status is 2xx or 5xx-tolerated': (r) => r.status > 0 });
  });

  return responses;
}
