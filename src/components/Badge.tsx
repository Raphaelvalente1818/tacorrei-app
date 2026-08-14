export default function Badge({ className, children }: { className: string; children: React.ReactNode }) {
  return (
    <span
      className={`inline-flex items-center border rounded-full px-2.5 py-1 text-xs font-bold whitespace-nowrap ${className}`}
    >
      {children}
    </span>
  )
}
