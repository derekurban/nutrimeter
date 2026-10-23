import { today } from './lib/dates'
import { useRoute } from './lib/router'
import { CustomFoodsPage } from './pages/CustomFoodsPage'
import { DiaryPage } from './pages/DiaryPage'
import { RecipesPage } from './pages/RecipesPage'
import { TargetsPage } from './pages/TargetsPage'

const NAV = [
  { key: 'diary', label: 'Diary', href: '#/diary' },
  { key: 'recipes', label: 'Recipes', href: '#/recipes' },
  { key: 'foods', label: 'Custom Foods', href: '#/foods' },
  { key: 'targets', label: 'Targets', href: '#/targets' },
]

export default function App() {
  const [section = 'diary', param] = useRoute()

  let page
  switch (section) {
    case 'recipes':
      page = <RecipesPage id={param} />
      break
    case 'foods':
      page = <CustomFoodsPage id={param} />
      break
    case 'targets':
      page = <TargetsPage />
      break
    default:
      page = <DiaryPage date={param && /^\d{4}-\d{2}-\d{2}$/.test(param) ? param : today()} />
  }

  return (
    <div className="app">
      <header className="topbar">
        <a className="brand" href="#/diary">
          <img src="/favicon.svg" alt="" />
          Nutrimeter
        </a>
        <nav>
          {NAV.map((n) => (
            <a key={n.key} href={n.href} className={section === n.key || (n.key === 'diary' && !NAV.some((x) => x.key === section)) ? 'active' : ''}>
              {n.label}
            </a>
          ))}
        </nav>
        <span className="topbar-note">
          Food data ©{' '}
          <a href="https://world.openfoodfacts.org" target="_blank" rel="noreferrer">
            Open Food Facts
          </a>{' '}
          (ODbL)
        </span>
      </header>
      <main>{page}</main>
    </div>
  )
}
