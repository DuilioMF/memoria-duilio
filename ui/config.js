// Producción: endpoint autenticado; requiere sesión Supabase del dueño.
// Configuración segura por defecto.
// El hosting puede reemplazar window.MEMORIA_CONFIG antes de cargar app.js.
window.MEMORIA_CONFIG = window.MEMORIA_CONFIG || {
  apiUrl: "https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-home-auth-v1",
  semanticUrl: "https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-duilio-semantic",
  supabaseUrl: "https://pddsehshgfynpmibjqhj.supabase.co",
  anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBkZHNlaHNoZ2Z5bnBtaWJqcWhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQwODMwNDUsImV4cCI6MjA1OTY1OTA0NX0._fsWtieONLOqZyBRp9Yb4UBviGKCA3xvjHcLzvvU5RU",
  accessToken: ""
};
