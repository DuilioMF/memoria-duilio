// Configuración segura por defecto.
// El hosting puede reemplazar window.MEMORIA_CONFIG antes de cargar app.js.
window.MEMORIA_CONFIG = window.MEMORIA_CONFIG || {
  apiUrl: "https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-home",
  semanticUrl: "https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-duilio-semantic",
  supabaseUrl: "https://pddsehshgfynpmibjqhj.supabase.co",
  anonKey: "",
  accessToken: ""
};
