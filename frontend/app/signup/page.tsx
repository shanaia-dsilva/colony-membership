"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import { useRouter } from "next/navigation";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSignup(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    setLoading(true);

    const { error } = await supabase.auth.signUp({ email, password });

    setLoading(false);
    if (error) return setErr(error.message);

    router.push("/dashboard"); // if email confirmation is ON, you may instead show “check email”
  }

  return (
    <main style={{ padding: 24, maxWidth: 420 }}>
      <h1>Signup</h1>
      <form onSubmit={onSignup}>
        <input placeholder="Email" value={email} onChange={(e)=>setEmail(e.target.value)} />
        <br />
        <input placeholder="Password" type="password" value={password} onChange={(e)=>setPassword(e.target.value)} />
        <br />
        <button disabled={loading}>{loading ? "Creating..." : "Signup"}</button>
      </form>
      {err && <p style={{ color: "red" }}>{err}</p>}
      <p>
        Have an account? <a href="/login">Login</a>
      </p>
    </main>
  );
}