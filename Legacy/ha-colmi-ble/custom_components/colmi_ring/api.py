"""Sample API Client."""

from __future__ import annotations

import datetime
import socket
from typing import Any

import aiohttp
import async_timeout

from colmi_r02_client import client


class ColmiRingApiClientError(Exception):
    """Exception to indicate a general API error."""


class ColmiRingApiClientCommunicationError(
    ColmiRingApiClientError,
):
    """Exception to indicate a communication error."""


class ColmiRingApiClientAuthenticationError(
    ColmiRingApiClientError,
):
    """Exception to indicate an authentication error."""


def _verify_response_or_raise(response: aiohttp.ClientResponse) -> None:
    """Verify that the response is valid."""
    if response.status in (401, 403):
        msg = "Invalid credentials"
        raise ColmiRingApiClientAuthenticationError(
            msg,
        )
    response.raise_for_status()


class ColmiRingApiClient:
    """Sample API Client."""

    # TODO: refactor the client's internal Bleak client to obey these rules
    # https://developers.home-assistant.io/docs/bluetooth#best-practices-for-integration-authors

    def __init__(self, ring_address: str) -> None:
        """Sample API Client."""
        self._ring_address = ring_address
        self._colmi_client = client.Client(self._ring_address)

    async def async_get_data(self) -> Any:
        """Get the most recent heart rate from the API."""
        end_time = datetime.datetime.now(datetime.timezone.utc)  # Current UTC time
        start_time = end_time - datetime.timedelta(hours=1)  # One hour ago

        async with client.Client(self._ring_address) as ring_client:
            full_data = await ring_client.get_full_data(start_time, end_time)

            # Extract heart rates with timestamps
            heart_rate_entries = []
            for entry in full_data.heart_rates:
                if isinstance(entry, client.hr.HeartRateLog):
                    heart_rate_entries.extend(
                        # Filter out 0's. Since we have 5m intervals and heart rate
                        # is only measured every 15 minutes, most entries are 0.
                        [r for r in entry.heart_rates_with_times() if r[0] > 0]
                    )  # [(heart rate, timestamp), ...]

            # Get the most recent heart rate
            if heart_rate_entries:
                latest_heart_rate, _ = max(heart_rate_entries, key=lambda x: x[1])
                # TODO: return more complex info, like the timestamp dropped on prev line.
                return {"heart_rate": latest_heart_rate}

            return None  # No heart rate data available

    async def async_set_time(self, value: datetime.datetime) -> Any:
        async with client.Client(self._ring_address) as ring_client:
            return await ring_client.set_time(value)

    async def async_blink_twice(self) -> Any:
        async with client.Client(self._ring_address) as ring_client:
            return await ring_client.blink_twice()

    async def async_reboot(self) -> Any:
        async with client.Client(self._ring_address) as ring_client:
            return await ring_client.reboot()
