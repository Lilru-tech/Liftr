import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')

serve(async (req) => {
  try {
    const { record } = await req.json()

    // Enviamos el email usando Resend
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: 'Supabase <onboarding@resend.dev>',
        to: ['d.g.sanc@gmail.com'], // CAMBIA ESTO POR TU EMAIL REAL
        subject: '🚀 ¡Nuevo usuario en Liftr!',
        html: `
          <h1>¡Alguien se acaba de registrar!</h1>
          <p><strong>Email:</strong> ${record.email}</p>
          <p><strong>ID de usuario:</strong> ${record.id}</p>
          <p>Fecha: ${new Date().toLocaleString()}</p>
        `,
      }),
    })

    const data = await res.json()
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})
