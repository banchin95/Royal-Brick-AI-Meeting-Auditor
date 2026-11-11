"""Keep the same timeout semantics on Ubuntu 22.04's Python 3.10."""

try:
    from asyncio import timeout
except ImportError:
    from async_timeout import timeout
