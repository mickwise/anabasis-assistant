"""
Purpose
-------
Provide a small, project-wide psycopg3 adapter for connecting to Postgres and
running transactions.

Key behaviors
-------------
- Builds connection configuration from either an explicit DSN or environment
  variables.
- Opens and closes psycopg3 connections via a context manager.
- Provides a transaction context manager that commits on success and rolls back
  on error.
- Optionally configures row factories for dict-like row access.

Conventions
-----------
- `DATABASE_URL` is the preferred configuration input.
- If `DATABASE_URL` is not set, standard `PG*` environment variables are used.
- Transactions are explicit: callers should use `tx(conn)` around a unit of
  work.

Downstream usage
----------------
ETL and other application code should call `connect(...)` to obtain a
connection, then use `tx(conn)` for transactional units of work.
"""

from __future__ import annotations

import os
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Generator, Optional, Union

import psycopg
from psycopg import Connection
from psycopg.rows import dict_row


@dataclass(frozen=True)
class DBConfig:
    """
    Purpose
    -------
    Represent Postgres connection configuration in a structured form.

    Key behaviors
    -------------
    - Can be created from a DSN string, or from discrete host/user/password
      components.
    - Can be loaded from environment variables via `from_env()`.

    Parameters
    ----------
    dsn : Optional[str]
        Full Postgres DSN, e.g. "postgresql://user:pass@host:5432/db".
        If provided, it takes precedence over the discrete fields.
    host : Optional[str]
        Postgres host (PGHOST).
    port : Optional[int]
        Postgres port (PGPORT).
    dbname : Optional[str]
        Postgres database name (PGDATABASE).
    user : Optional[str]
        Postgres user (PGUSER).
    password : Optional[str]
        Postgres password (PGPASSWORD).
    sslmode : Optional[str]
        SSL mode (PGSSLMODE). Examples: "disable", "require".

    Attributes
    ----------
    dsn : Optional[str]
        Full Postgres DSN.
    host : Optional[str]
        Postgres host.
    port : Optional[int]
        Postgres port.
    dbname : Optional[str]
        Postgres database name.
    user : Optional[str]
        Postgres user.
    password : Optional[str]
        Postgres password.
    sslmode : Optional[str]
        SSL mode.

    Notes
    -----
    - This class does not validate connectivity.
    - `dsn` (if set) is treated as authoritative.
    """

    dsn: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    dbname: Optional[str] = None
    user: Optional[str] = None
    password: Optional[str] = None
    sslmode: Optional[str] = None

    @classmethod
    def from_env(cls) -> "DBConfig":
        """
        Build DBConfig from environment variables.

        Parameters
        ----------
        None

        Returns
        -------
        DBConfig
            Configuration loaded from `DATABASE_URL` when present, otherwise
            from `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, and
            optional `PGSSLMODE`.

        Raises
        ------
        ValueError
            If configuration is incomplete and no DSN is provided.

        Notes
        -----
        - `DATABASE_URL` is treated as authoritative when present.
        - If `PGPORT` is set, it is parsed as an integer.
        """

        dsn = os.getenv("DATABASE_URL")
        if dsn:
            return cls(dsn=dsn)

        host = os.getenv("PGHOST")
        port_raw = os.getenv("PGPORT")
        dbname = os.getenv("PGDATABASE")
        user = os.getenv("PGUSER")
        password = os.getenv("PGPASSWORD")
        sslmode = os.getenv("PGSSLMODE")

        port: Optional[int]
        if port_raw is None or port_raw == "":
            port = None
        else:
            port = int(port_raw)

        if not (host and dbname and user):
            raise ValueError(
                "Missing DB config; set DATABASE_URL or PGHOST/PGDATABASE/PGUSER"
            )

        return cls(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=password,
            sslmode=sslmode,
        )


def as_dsn(cfg: DBConfig) -> str:
    """
    Convert a DBConfig into a psycopg connection string.

    Parameters
    ----------
    cfg : DBConfig
        Database configuration.

    Returns
    -------
    str
        A Postgres DSN suitable for `psycopg.connect(...)`.

    Raises
    ------
    ValueError
        If the configuration is incomplete and no `dsn` is set.

    Notes
    -----
    - If `cfg.dsn` is set, it is returned unchanged.
    - Otherwise a libpq-style DSN is built from the discrete fields.
    """

    if cfg.dsn:
        return cfg.dsn

    if not (cfg.host and cfg.dbname and cfg.user):
        raise ValueError("Incomplete DBConfig; cannot build DSN")

    parts: list[str] = [
        f"host={cfg.host}",
        f"dbname={cfg.dbname}",
        f"user={cfg.user}",
    ]

    if cfg.port is not None:
        parts.append(f"port={cfg.port}")

    if cfg.password is not None:
        parts.append(f"password={cfg.password}")

    if cfg.sslmode is not None:
        parts.append(f"sslmode={cfg.sslmode}")

    return " ".join(parts)


@contextmanager
def connect(
    dsn_or_cfg: Union[str, DBConfig],
) -> Generator[Connection[Any], None, None]:
    """
    Open a psycopg3 connection and ensure it is closed.

    Parameters
    ----------
    dsn_or_cfg : Union[str, DBConfig]
        Either a DSN string or a DBConfig object.

    Returns
    -------
    Generator[psycopg.Connection[Any], None, None]
        A context manager yielding an open psycopg connection.

    Raises
    ------
    psycopg.Error
        If psycopg fails to connect.

    Notes
    -----
    - The connection is always closed at context exit.
    - Autocommit is left as psycopg default (False).
    """

    dsn = dsn_or_cfg if isinstance(dsn_or_cfg, str) else as_dsn(dsn_or_cfg)
    conn: Connection[Any] = psycopg.connect(dsn)
    try:
        yield conn
    finally:
        conn.close() # pylint: disable=no-member


@contextmanager
def tx(conn: Connection[Any]) -> Generator[None, None, None]:
    """

    Run a transactional unit of work.

    Parameters
    ----------
    conn : psycopg.Connection[Any]
        Open psycopg connection.

    Returns
    -------
    None
        Yields control to the caller within a transaction.

    Raises
    ------
    Exception
        Re-raises any exception from the caller after rolling back.

    Notes
    -----
    - Commits on successful context exit.
    - Rolls back on error.
    """

    try:
        with conn.transaction():
            yield
    except Exception: # pylint: disable=try-except-raise
        raise


def dict_rows(conn: Connection[Any]) -> None:
    """

    Configure a psycopg connection to return dict-like rows.

    Parameters
    ----------
    conn : psycopg.Connection[Any]
        Open psycopg connection to configure.

    Returns
    -------
    None
        This function mutates the connection's row factory.

    Raises
    ------
    None

    Notes
    -----
    - This sets `conn.row_factory` to `psycopg.rows.dict_row`.
    - Callers can alternatively pass `row_factory=dict_row` per cursor.
    """

    conn.row_factory = dict_row
