EXTENSION = pg_eyes
DATA = sql/pg_eyes--*.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
