"""Small asyncio broadcast helper."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Generic, TypeVar

T = TypeVar("T")


class Broadcaster(Generic[T]):
    def __init__(self, max_queue: int = 32) -> None:
        self._max_queue = max_queue
        self._queues: set[asyncio.Queue[T]] = set()

    @asynccontextmanager
    async def subscribe(self) -> AsyncIterator[asyncio.Queue[T]]:
        queue: asyncio.Queue[T] = asyncio.Queue(maxsize=self._max_queue)
        self._queues.add(queue)
        try:
            yield queue
        finally:
            self._queues.discard(queue)

    def publish(self, item: T) -> None:
        stale: list[asyncio.Queue[T]] = []
        for queue in list(self._queues):
            try:
                queue.put_nowait(item)
            except asyncio.QueueFull:
                try:
                    queue.get_nowait()
                    queue.put_nowait(item)
                except asyncio.QueueEmpty:
                    stale.append(queue)
        for queue in stale:
            self._queues.discard(queue)

