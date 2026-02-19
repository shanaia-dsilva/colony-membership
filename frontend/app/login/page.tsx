"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import { useRouter } from "next/navigation";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onLogin(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    setLoading(true);

    const { error } = await supabase.auth.signInWithPassword({ email, password });

    setLoading(false);
    if (error) return setErr(error.message);

    router.push("/dashboard");
  }

  return (
    <main style={{ padding: 24, maxWidth: 420 }}>
      <h1>Login</h1>
      <form onSubmit={onLogin}>
        <input placeholder="Email" value={email} onChange={(e)=>setEmail(e.target.value)} />
        <br />
        <input placeholder="Password" type="password" value={password} onChange={(e)=>setPassword(e.target.value)} />
        <br />
        <button disabled={loading}>{loading ? "Logging in..." : "Login"}</button>
      </form>
      {err && <p style={{ color: "red" }}>{err}</p>}
      <p>
        New? <a href="/signup">Signup</a>
      </p>
    </main>
  );
}