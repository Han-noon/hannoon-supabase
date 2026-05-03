create trigger set_updated_at
before update on articles
for each row
execute function update_updated_at();