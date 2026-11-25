import { useEffect, useRef, useState } from 'react';

export default function useLoans(apiBase, userId) {
  const [loans, setLoans] = useState([]);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const generation = useRef(0);
  const owner = useRef(userId);
  owner.current = userId;

  useEffect(() => {
    let active = true;
    const abort = new AbortController();
    setLoans([]);
    setLoaded(false);
    setError('');
    const refresh = async () => {
      if (!userId || lock.current) return;
      const version = ++generation.current;
      try {
        const response = await fetch(`${apiBase}/loans?user_id=${encodeURIComponent(userId)}`, { signal: abort.signal });
        if (!response.ok) throw new Error('Could not load borrowed and lent money.');
        const data = await response.json();
        if (!Array.isArray(data)) throw new Error('Unexpected loan response.');
        if (active && version === generation.current) {
          setLoans(data); setLoaded(true); setError('');
        }
      } catch (e) {
        if (active && version === generation.current && e.name !== 'AbortError') setError(`${e.message} Retrying shortly.`);
      }
    };
    refresh();
    const timer = setInterval(refresh, 15000);
    return () => { active = false; abort.abort(); clearInterval(timer); };
  }, [apiBase, userId]);

  const mutate = async (method, id, body) => {
    if (lock.current) return false;
    lock.current = true;
    ++generation.current;
    setBusy(true); setError('');
    try {
      const path = id == null ? '/loans' : `/loans/${id}?user_id=${encodeURIComponent(userId)}`;
      const response = await fetch(`${apiBase}${path}`, {
        method, headers: { 'Content-Type': 'application/json' },
        ...(body ? { body: JSON.stringify(id == null ? { ...body, user_id: userId } : body) } : {}),
      });
      if (!response.ok) {
        const payload = await response.json();
        throw new Error(typeof payload.detail === 'string' ? payload.detail : 'Could not save this entry. Check the details and retry.');
      }
      const updated = await response.json();
      if (owner.current === userId) {
        setLoans(items => method === 'DELETE' ? items.filter(item => item.id !== id)
          : id == null ? [updated, ...items] : items.map(item => item.id === id ? updated : item));
      }
      return true;
    } catch (e) {
      if (owner.current === userId) setError(`${e.message} Refresh before retrying if the connection was interrupted.`);
      return false;
    } finally {
      lock.current = false; setBusy(false);
    }
  };
  return { loans, loaded, error, busy, mutate };
}
