import { defineConfig } from "vite";
import checker from "vite-plugin-checker";

// https://vitejs.dev/config/
export default defineConfig({
  build: {
    target: "chrome118",
  },
  server: {
    port: 5005,
    host: true,
  },
  plugins: [
    checker({
      typescript: true,
    }),
  ],
});
