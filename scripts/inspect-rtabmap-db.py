#!/usr/bin/env python3
"""Print RTAB-Map database graph table details without modifying the database."""

import argparse
import sqlite3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("database")
    args = parser.parse_args()

    connection = sqlite3.connect(f"file:{args.database}?mode=ro", uri=True)
    try:
        tables = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        ]
        print("Tables:", ", ".join(tables))

        for table in ("Link", "Node", "Data"):
            if table not in tables:
                continue

            columns = [row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')]
            print(f"{table} columns:", ", ".join(columns))
            count = connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
            print(f"{table} rows:", count)

            if table == "Link":
                rows = connection.execute(
                    'SELECT from_id, to_id, type FROM "Link" '
                    "ORDER BY from_id, to_id LIMIT 20"
                ).fetchall()
                print("Link sample:", rows)

            if table == "Data":
                size_columns = [
                    column
                    for column in ("image", "depth", "laser_scan", "occupancy_grid")
                    if column in columns
                ]
                expression = ", ".join(
                    f'length("{column}") AS "{column}_bytes"'
                    for column in size_columns
                )
                rows = connection.execute(
                    f'SELECT id, {expression} FROM "Data" '
                    "WHERE id IN (1, 646, 892) ORDER BY id"
                ).fetchall()
                print("Data sample sizes:", rows)
    finally:
        connection.close()


if __name__ == "__main__":
    main()
