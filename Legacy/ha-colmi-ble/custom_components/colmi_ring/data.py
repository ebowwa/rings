"""Custom types for colmi_ring."""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.loader import Integration

    from .api import ColmiRingApiClient
    from .coordinator import ColmiRingDataUpdateCoordinator


type ColmiRingConfigEntry = ConfigEntry[ColmiRingData]


@dataclass
class ColmiRingData:
    """Data for the Blueprint integration."""

    client: ColmiRingApiClient
    coordinator: ColmiRingDataUpdateCoordinator
    integration: Integration
