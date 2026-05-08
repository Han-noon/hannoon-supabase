create trigger set_updated_at
before update on public.articles
for each row
execute function public.update_updated_at();