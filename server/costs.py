"""Read Cloud Billing export data for Veya's internal dashboard."""
from __future__ import annotations

import os
import time
from threading import Lock


class CloudBillingCosts:
    """Small cached reader so a dashboard refresh never creates query storms."""

    def __init__(self) -> None:
        self.project = os.environ.get('GOOGLE_CLOUD_PROJECT', '').strip()
        self.dataset = os.environ.get('VEYA_BILLING_DATASET', '').strip()
        self._cached: dict[str, object] | None = None
        self._cached_at = 0.0
        self._lock = Lock()

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            if self._cached and time.time() - self._cached_at < 600:
                return self._cached
            self._cached = self._read()
            self._cached_at = time.time()
            return self._cached

    def _read(self) -> dict[str, object]:
        if not self.dataset:
            return self._status('not_configured', 'Cloud Billing export has not been configured.')
        try:
            from google.cloud import bigquery
        except ImportError:
            return self._status('not_available', 'BigQuery reader is not installed on the gateway.')

        try:
            client = bigquery.Client(project=self.project or None)
            dataset = client.dataset(self.dataset, project=self.project or None)
            table = next(
                (
                    item.table_id for item in client.list_tables(dataset)
                    if item.table_id.startswith('gcp_billing_export_v1_')
                ),
                None,
            )
            if not table:
                return self._status(
                    'collecting',
                    'Billing export is enabled. Google publishes the first daily cost table within about 24 hours.',
                )
            table_ref = f'`{dataset.project}.{self.dataset}.{table}`'
            query = f'''
                SELECT
                  service.description AS service,
                  currency,
                  ROUND(SUM(cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS amount
                FROM {table_ref}
                WHERE DATE(usage_start_time, "Asia/Kolkata") >= DATE_TRUNC(CURRENT_DATE("Asia/Kolkata"), MONTH)
                GROUP BY service, currency
                ORDER BY amount DESC
            '''
            rows = list(client.query(query).result())
            services = [
                {'name': str(row.service), 'amount': float(row.amount or 0), 'currency': str(row.currency)}
                for row in rows
            ]
            currency = services[0]['currency'] if services else 'INR'
            return {
                'status': 'available',
                'source': 'Google Cloud Billing export',
                'message': 'Current-month net cost after credits.',
                'currency': currency,
                'month_to_date': round(sum(item['amount'] for item in services), 2),
                'services': services,
                'updated_at': int(time.time()),
            }
        except Exception as error:
            print(f'Veya billing dashboard read failed: {error!r}', flush=True)
            return self._status('unavailable', 'Cloud Billing data is temporarily unavailable. Please refresh later.')

    @staticmethod
    def _status(status: str, message: str) -> dict[str, object]:
        return {
            'status': status,
            'source': 'Google Cloud Billing export',
            'message': message,
            'currency': 'INR',
            'month_to_date': None,
            'services': [],
            'updated_at': int(time.time()),
        }
