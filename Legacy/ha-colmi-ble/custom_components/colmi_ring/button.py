"""Button platform for colmi_ring."""

from __future__ import annotations

from typing import TYPE_CHECKING

from homeassistant.components.button import ButtonEntity, ButtonEntityDescription

from .entity import ColmiRingEntity

if TYPE_CHECKING:
    from homeassistant.core import HomeAssistant
    from homeassistant.helpers.entity_platform import AddEntitiesCallback

    from .coordinator import ColmiRingDataUpdateCoordinator
    from .data import ColmiRingConfigEntry


async def async_setup_entry(
    hass: HomeAssistant,  # noqa: ARG001 Unused function argument: `hass`
    entry: ColmiRingConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the button platform."""
    async_add_entities(
        [
            ColmiRingBlinkButton(
                coordinator=entry.runtime_data.coordinator,
                entity_description=ButtonEntityDescription(
                    key="colmi_ring_blink_button",
                    name="Blink Twice",
                    icon="mdi:eye-outline",
                ),
            ),
            ColmiRingRebootButton(
                coordinator=entry.runtime_data.coordinator,
                entity_description=ButtonEntityDescription(
                    key="colmi_ring_reboot_button",
                    name="Reboot",
                    icon="mdi:restart",
                ),
            ),
        ]
    )


class ColmiRingBlinkButton(ColmiRingEntity, ButtonEntity):
    """colmi_ring button class."""

    def __init__(
        self,
        coordinator: ColmiRingDataUpdateCoordinator,
        entity_description: ButtonEntityDescription,
    ) -> None:
        """Initialize the button class."""
        super().__init__(coordinator)
        self.entity_description = entity_description
        self._attr_unique_id = (
            f"{coordinator.config_entry.entry_id}_{entity_description.key}"
        )

    def press(self) -> None:
        """Press the button."""
        self.hass.async_create_task(self.async_press())

    async def async_press(self) -> None:
        """Press the button."""
        await self.coordinator.config_entry.runtime_data.client.async_blink_twice()


class ColmiRingRebootButton(ColmiRingEntity, ButtonEntity):
    """colmi_ring button class."""

    def __init__(
        self,
        coordinator: ColmiRingDataUpdateCoordinator,
        entity_description: ButtonEntityDescription,
    ) -> None:
        """Initialize the button class."""
        super().__init__(coordinator)
        self.entity_description = entity_description
        self._attr_unique_id = (
            f"{coordinator.config_entry.entry_id}_{entity_description.key}"
        )

    def press(self) -> None:
        """Press the button."""
        self.hass.async_create_task(self.async_press())

    async def async_press(self) -> None:
        """Press the button."""
        await self.coordinator.config_entry.runtime_data.client.async_reboot()
