import redis
from config import settings

class SafeRedisClient:
    def __init__(self, url: str):
        self._client = redis.Redis.from_url(url, decode_responses=True)

    def exists(self, key: str) -> bool:
        try:
            return bool(self._client.exists(key))
        except redis.RedisError:
            return False

    def setex(self, key: str, seconds: int, value: str) -> bool:
        try:
            return bool(self._client.setex(key, seconds, value))
        except redis.RedisError:
            return False

    def get(self, key: str):
        try:
            return self._client.get(key)
        except redis.RedisError:
            return None

    def delete(self, key: str) -> int:
        try:
            return int(self._client.delete(key))
        except redis.RedisError:
            return 0

    def scan_iter(self, pattern: str):
        try:
            yield from self._client.scan_iter(pattern)
        except redis.RedisError:
            return

    def ping(self) -> bool:
        try:
            return bool(self._client.ping())
        except redis.RedisError:
            return False


redis_client = SafeRedisClient(settings.redis_url)
